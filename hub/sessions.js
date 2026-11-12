import pty from 'node-pty';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { execFile, execFileSync } from 'node:child_process';
import { EventLog } from './eventlog.js';
import { load, save } from './store.js';
import { Tailer, parseLine, findTranscript, latestEntrypoint, liveReferences } from './transcript.js';

export function scrubEnv(env) {
  return Object.fromEntries(Object.entries(env).filter(([k, v]) => v != null && !/^CLAUDE/i.test(k)));
}

export function resolveClaude() {
  if (process.env.ECHO_CLAUDE) return [process.env.ECHO_CLAUDE];
  if (process.platform === 'win32') {
    try {
      const exe = execFileSync('where.exe', ['claude'], { encoding: 'utf8' })
        .split(/\r?\n/).find((l) => l.toLowerCase().endsWith('.exe'));
      if (exe) return [exe.trim()];
    } catch {}
    return [path.join(process.env.USERPROFILE || '', '.local', 'bin', 'claude.exe')];
  }
  return [execFileSync('sh', ['-c', 'command -v claude'], { encoding: 'utf8' }).trim()];
}

const NEXT = {
  data: { starting: 'running' },
  input: { starting: 'running', running: 'running', waiting: 'running', done: 'running' },
  stop: { starting: 'done', running: 'done', waiting: 'done' },
  notification: { starting: 'waiting', running: 'waiting', done: 'waiting' },
  exit: { starting: 'exited', running: 'exited', waiting: 'exited', done: 'exited' },
  boot: { starting: 'stopped', running: 'stopped', waiting: 'stopped', done: 'stopped' },
};
// exited, stopped, external are absent from every row, so they never change
export const transition = (state, signal) => NEXT[signal]?.[state] ?? state;

// D-17: whole process tree. Only #killOwned and the boot sweep may call this. posix: node-pty makes the child a session leader, so -pid is its group.
export function killTree(pid) {
  if (process.platform === 'win32') execFile('taskkill', ['/PID', String(pid), '/T', '/F'], () => {});
  else { try { process.kill(-pid, 'SIGKILL'); } catch {} }
}

// P0-1: only a process whose command line carries THIS session id is ours. A bare /claude/ match
// can hit Even Terminal's per-turn `claude --resume` after PID reuse. Windows: no cmdline check yet → never sweep-kill.
const ownsSession = (pid, id) => {
  if (process.platform === 'win32' || !id) return false;
  try {
    const out = execFileSync('ps', ['-p', String(pid), '-o', 'command='], { encoding: 'utf8' });
    return /claude/i.test(out) && out.includes(id);
  } catch { return false; }
};
// P0-1: a stored pid whose parent is Even Terminal belongs to it. Fail closed on any error.
export function parentIsEvenTerminal(pid) {
  if (process.platform === 'win32') return true;
  try {
    const ppid = execFileSync('ps', ['-p', String(pid), '-o', 'ppid='], { encoding: 'utf8' }).trim();
    if (!/^\d+$/.test(ppid)) return true;
    return /even-terminal/i.test(execFileSync('ps', ['-p', ppid, '-o', 'command='], { encoding: 'utf8' }));
  } catch { return true; }
}
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };
const fail = (code) => Object.assign(new Error(code), { code });

const STOP_DEBOUNCE_MS = 1500;
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, Math.floor(+n) || lo));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class Sessions {
  #map = new Map();
  #spawned = new Set(); // pids this hub process spawned this boot
  constructor({ claudeCmd, epoch, dataDir, projectsDir, extraArgs = () => [], extraEnv = {}, onAlert = () => {}, stallMs = 120000 }) {
    Object.assign(this, { claudeCmd, epoch, dataDir, projectsDir, extraArgs, extraEnv, onAlert, stallMs });
    this.file = path.join(dataDir, 'sessions.json');
    this.prior = load(this.file, []);
    let changed = false, swept = 0;
    for (const p of this.prior) {
      if (p.source !== 'hub') continue;
      const n = transition(p.state, 'boot');
      if (n === p.state) continue;
      // T-01-15: a reused PID must not be killed unless it still looks like claude
      if (p.pid > 1 && alive(p.pid) && ownsSession(p.pid, p.id) && !parentIsEvenTerminal(p.pid)) {
        console.log(`kill pid ${p.pid} ${String(p.id).slice(0, 8)} boot-sweep`); killTree(p.pid); swept++;
      }
      p.state = n; changed = true;
    }
    if (changed) save(this.file, this.prior);
    console.log(`swept ${swept}`);
    if (process.platform !== 'win32') {
      try { // Pitfall 1: darwin prebuild ships spawn-helper 0644
        const dir = path.dirname(createRequire(import.meta.url).resolve('node-pty'));
        fs.chmodSync(path.join(dir, '..', 'prebuilds', `${process.platform}-${process.arch}`, 'spawn-helper'), 0o755);
      } catch {}
    }
  }

  selfTest() {
    return new Promise((resolve) => {
      let out = '';
      let p;
      const t = setTimeout(() => { try { p.kill(); } catch {} resolve({ ok: false }); }, 10000);
      try {
        p = pty.spawn(this.claudeCmd[0], [...this.claudeCmd.slice(1), '--version'], {
          name: 'xterm-256color', cols: 120, rows: 30, env: scrubEnv(process.env),
        });
      } catch { clearTimeout(t); return resolve({ ok: false }); }
      p.onData((d) => { out += d; });
      p.onExit(({ exitCode }) => { clearTimeout(t); resolve({ ok: exitCode === 0, version: out.trim() }); });
    });
  }

  // ponytail: externals are never persisted; discovery rebuilds them
  #persist() { save(this.file, this.list().filter((s) => s.source === 'hub')); }

  // chat events from the transcript; hub sessions poll until claude has created the file
  #tail(s, file) {
    s.caughtUp = false;
    s.tailer = new Tailer(file, (o) => {
      for (const m of parseLine(o)) s.log.append('chat', m);
      if (s.source === 'external' && s.caughtUp) this.#extTurn(s, o);
    }).start();
    s.caughtUp = true; // catch-up (first poll) never alerts
  }

  // D-02: external alerts come from the transcript alone
  #extTurn(s, o) {
    clearTimeout(s.stallTimer);
    if (o?.type !== 'assistant') return;
    const stop = o.message?.stop_reason;
    if (stop === 'end_turn') {
      s.lastStop = (Array.isArray(o.message.content) ? o.message.content : []).filter((b) => b?.type === 'text').map((b) => b.text).join('\n');
      clearTimeout(s.stopTimer);
      s.stopTimer = setTimeout(() => this.#alert(s, 'done'), STOP_DEBOUNCE_MS);
    } else if (stop === 'tool_use') {
      s.stallTimer = setTimeout(() => { s.lastMessage = 'may need you'; this.#alert(s, 'waiting'); }, this.stallMs);
      s.stallTimer.unref();
    }
  }

  #findTail(s) {
    const t = setInterval(() => {
      const f = findTranscript(this.projectsDir, s.id);
      if (f) { clearInterval(t); this.#tail(s, f); }
    }, 1000);
    t.unref();
    s.findTimer = t;
  }

  addExternal({ id, cwd, label, title, transcriptPath, entrypoint }) {
    const s = this.get(id);
    if (s) {
      if (s.source === 'external') Object.assign(s, { label, title, entrypoint, cwd: cwd || s.cwd, discovered: true });
      return;
    }
    const e = { id, cwd, pid: 0, state: 'external', source: 'external', label, title, entrypoint, transcriptPath, discovered: true,
      startedAt: new Date().toISOString(), log: new EventLog(), pty: null };
    this.#map.set(id, e);
    this.#tail(e, transcriptPath);
  }

  pruneExternals(seen) {
    for (const s of this.#map.values()) {
      if (s.discovered && !seen.has(s.id)) { s.tailer?.stop(); clearTimeout(s.stopTimer); clearTimeout(s.stallTimer); this.#map.delete(s.id); }
    }
  }

  ownedIds() { return new Set([...this.#map.values()].filter((s) => s.source === 'hub').map((s) => s.id)); }

  close() {
    for (const s of this.#map.values()) { s.tailer?.stop(); clearInterval(s.findTimer); clearTimeout(s.stopTimer); clearTimeout(s.stallTimer); }
  }

  start({ cwd, prompt }) {
    if (typeof cwd !== 'string' || !path.isAbsolute(cwd) || !fs.existsSync(cwd) || !fs.statSync(cwd).isDirectory()) {
      throw Object.assign(new Error('cwd must be an absolute existing directory'), { code: 'bad_cwd' });
    }
    const id = crypto.randomUUID();
    const prefix = this.claudeCmd.slice(1);
    const s = { id, cwd, pid: 0, state: 'starting', source: 'hub', startedAt: new Date().toISOString(),
      log: new EventLog(), pty: null, cols: 120, rows: 30, q: Promise.resolve() };
    this.#spawn(s, [...prefix, '--session-id', id, ...this.extraArgs(id), ...(prompt ? [prompt] : [])]);
    this.#findTail(s);
    return s;
  }

  // shared by start/resume/takeover: PTY + coalesced term events + exit handling
  #spawn(s, args) {
    const id = s.id;
    s.pty = pty.spawn(this.claudeCmd[0], args, {
      name: 'xterm-256color', cols: s.cols, rows: s.rows, cwd: s.cwd,
      env: { ...scrubEnv(process.env), ...this.extraEnv },
    });
    s.pid = s.pty.pid;
    this.#spawned.add(s.pid);
    this.#map.set(id, s);
    this.#persist();
    // coalesce PTY output into one term event per 25 ms
    let buf = '', timer = null;
    const flush = () => {
      timer = null;
      if (buf) s.log.append('term', { data: Buffer.from(buf, 'utf8').toString('base64') });
      buf = '';
    };
    const cur = s.pty; // a resumed record gets a new pty; ignore the old one's late events
    cur.onData((d) => {
      if (s.pty !== cur) return;
      this.signal(s.id, 'data');
      buf += d;
      timer ??= setTimeout(flush, 25);
    });
    cur.onExit(({ exitCode }) => {
      if (s.pty !== cur) return;
      s.exitCode = exitCode;
      this.#spawned.delete(cur.pid);
      s.tailer?.stop();
      clearTimeout(timer);
      clearTimeout(s.stopTimer);
      clearInterval(s.findTimer);
      flush();
      this.signal(s.id, 'exit');
    });
    const t = setTimeout(() => { if (s.state === 'starting') console.log(`starting timeout ${id.slice(0, 8)}`); }, 20000);
    t.unref();
  }

  // SESS-06 resume (exited / stopped hub session) and EXT-02 takeover (idle external session); same id kept
  resume(id, { takeover = false, liveIds = new Set() } = {}) {
    // D-03: never a second writer on Even Terminal's or any other live process's session; unknown = refuse
    const guard = (entry) => {
      if (entry === 'sdk-ts') throw fail('even_terminal');
      const refs = liveReferences(id, this.#spawned);
      if (refs === null || refs.length || liveIds.has(id)) throw fail('live_elsewhere');
    };
    let s = this.get(id);
    if (!s) {
      const p = this.prior.find((x) => x.id === id && x.source === 'hub');
      if (!p) throw fail('not_found');
      if (takeover || (p.state !== 'stopped' && p.state !== 'exited')) throw fail('not_resumable');
      s = { id, cwd: p.cwd, pid: 0, state: 'stopped', source: 'hub', startedAt: p.startedAt, title: p.title,
        log: new EventLog(), pty: null, cols: 120, rows: 30, q: Promise.resolve() };
      guard(latestEntrypoint(findTranscript(this.projectsDir, id)));
    } else if (s.source === 'external') {
      const f = s.transcriptPath ?? findTranscript(this.projectsDir, id);
      guard(s.entrypoint ?? latestEntrypoint(f));
      if (!takeover) throw fail('not_resumable');
      let mtime = 0;
      try { mtime = fs.statSync(f).mtimeMs; } catch {}
      if (liveIds.has(id) || Date.now() - mtime < 60000) throw fail('busy'); // D-08 two-writer guard
    } else {
      if (takeover || s.state !== 'exited') throw fail('not_resumable');
      guard(latestEntrypoint(findTranscript(this.projectsDir, id)));
    }
    if (typeof s.cwd !== 'string' || !path.isAbsolute(s.cwd) || !fs.existsSync(s.cwd) || !fs.statSync(s.cwd).isDirectory()) throw fail('bad_cwd');
    const wasExternal = s.source === 'external';
    if (wasExternal) { s.source = 'hub'; delete s.discovered; delete s.label; Object.assign(s, { pid: 0, cols: 120, rows: 30, q: Promise.resolve() }); }
    s.userStopped = false;
    this.#map.set(id, s);
    this.setState(s, 'starting');
    this.#spawn(s, [...this.claudeCmd.slice(1), '--resume', id, ...this.extraArgs(id)]);
    if (s.tailer && !wasExternal) s.tailer.start(); // keeps its byte offset: no duplicate chat
    else if (!s.tailer) this.#findTail(s);
    return s;
  }

  takeover(id, liveIds) { return this.resume(id, { takeover: true, liveIds }); }

  setState(s, state) {
    s.state = state;
    s.log.append('state', { state });
    this.#persist();
    if (s.source === 'hub' && (state === 'done' || state === 'waiting' || state === 'exited') && !(state === 'exited' && s.userStopped)) this.#alert(s, state);
  }

  #alert(s, kind) {
    try { this.onAlert(s, kind); } catch (e) { console.log(`alert failed ${e.message}`); } // never break state handling
  }

  signal(id, sig) {
    const s = this.get(id);
    if (!s) return;
    const next = transition(s.state, sig);
    if (next !== s.state) this.setState(s, next);
  }

  hook(p) {
    if (!p || typeof p !== 'object' || typeof p.session_id !== 'string' || typeof p.hook_event_name !== 'string') return;
    if (p.agent_id || p.hook_event_name === 'SubagentStop') return; // Pitfall 6
    const id = p.session_id;
    let s = this.get(id);
    if (!s) {
      if (!/^[0-9a-f-]{36}$/.test(id)) return;
      this.#map.set(id, { id, cwd: typeof p.cwd === 'string' ? p.cwd : '', pid: 0, state: 'external', source: 'external',
        label: 'Unknown', startedAt: new Date().toISOString(), log: new EventLog(), pty: null });
      const f = findTranscript(this.projectsDir, id);
      if (f) this.#tail(this.get(id), f);
      s = this.get(id);
    }
    const ext = s.source === 'external';
    if (p.hook_event_name === 'Stop') {
      if (typeof p.last_assistant_message === 'string') s.lastStop = p.last_assistant_message;
      clearTimeout(s.stopTimer);
      s.stopTimer = setTimeout(() => (ext ? this.#alert(s, 'done') : this.signal(id, 'stop')), STOP_DEBOUNCE_MS);
    } else if (p.hook_event_name === 'Notification') {
      s.lastMessage = p.message;
      if (ext) this.#alert(s, 'waiting');
      else this.signal(id, 'notification');
    }
  }

  get(id) { return this.#map.get(id); }

  list() {
    const live = [...this.#map.values()].map(({ id, cwd, pid, state, source, startedAt, label, title }) => ({ id, cwd, pid, state, source, startedAt, label, title }));
    const ids = new Set(live.map((s) => s.id));
    return [...this.prior.filter((p) => p.source !== 'external' && !ids.has(p.id)), ...live];
  }

  // D-19: guard, then one per-session promise chain so pastes never interleave
  #writable(id) {
    const s = this.get(id);
    if (!s) throw fail('not_found');
    if (s.source === 'external') throw fail('read_only');
    if (!s.pty || s.state === 'exited' || s.state === 'stopped') throw fail('not_running');
    return s;
  }

  enqueue(id, fn) {
    const s = this.#writable(id);
    const run = s.q.then(fn);
    s.q = run.catch((e) => console.log(`write failed ${e.message}`));
    return run;
  }

  async input(id, text) {
    return this.enqueue(id, async () => {
      const s = this.get(id);
      clearTimeout(s.stopTimer);
      this.signal(id, 'input');
      s.pty.write('\x1b[200~' + text + '\x1b[201~');
      await sleep(80);
      s.pty.write('\r');
    });
  }

  async keys(id, data) {
    return this.enqueue(id, () => {
      const s = this.get(id);
      clearTimeout(s.stopTimer);
      this.signal(id, 'input');
      s.pty.write(data);
    });
  }

  async interrupt(id) { return this.enqueue(id, () => this.get(id).pty.write('\x03')); } // D-18

  #killOwned(s, reason) {
    const id8 = String(s.id).slice(0, 8);
    if (!this.#spawned.has(s.pid)) { console.log(`kill refused pid ${s.pid} ${id8}`); return false; }
    console.log(`kill pid ${s.pid} ${id8} ${reason}`);
    killTree(s.pid);
    return true;
  }

  async stop(id) {
    const s = this.#writable(id);
    clearTimeout(s.stopTimer);
    s.userStopped = true; // 04-03 resume must reset this to false
    this.#killOwned(s, 'stop');
    if (process.platform === 'win32') { try { s.pty.kill(); } catch {} } // no signal arg on Windows (Pitfall 7)
    for (let i = 0; i < 100 && s.state !== 'exited'; i++) await sleep(50);
    if (s.state !== 'exited') this.signal(id, 'exit');
  }

  resize(id, cols, rows) {
    const s = this.get(id);
    if (!s?.pty || s.state === 'exited') return;
    s.cols = clamp(cols, 20, 500);
    s.rows = clamp(rows, 5, 200);
    s.pty.resize(s.cols, s.rows);
  }

  async nudge(id) {
    const s = this.get(id);
    if (!s?.pty || s.state === 'exited') return;
    const { cols, rows } = s;
    s.pty.resize(cols, rows + 1);
    await sleep(50);
    if (s.state !== 'exited') s.pty.resize(cols, rows);
  }

  killAll() {
    for (const s of this.#map.values()) { clearTimeout(s.stopTimer); try { s.pty.kill(); } catch {} }
  }
}
