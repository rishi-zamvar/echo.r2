import pty from 'node-pty';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { EventLog } from './eventlog.js';
import { load, save } from './store.js';

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

const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, Math.floor(+n) || lo));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class Sessions {
  #map = new Map();
  constructor({ claudeCmd, epoch, dataDir, extraArgs = () => [], extraEnv = {} }) {
    Object.assign(this, { claudeCmd, epoch, dataDir, extraArgs, extraEnv });
    this.file = path.join(dataDir, 'sessions.json');
    this.prior = load(this.file, []); // plan 02 marks these stopped
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

  #persist() { save(this.file, this.list()); }

  start({ cwd, prompt }) {
    if (typeof cwd !== 'string' || !path.isAbsolute(cwd) || !fs.existsSync(cwd) || !fs.statSync(cwd).isDirectory()) {
      throw Object.assign(new Error('cwd must be an absolute existing directory'), { code: 'bad_cwd' });
    }
    const id = crypto.randomUUID();
    const [file, ...prefix] = this.claudeCmd;
    const args = [...prefix, '--session-id', id, ...this.extraArgs(id), ...(prompt ? [prompt] : [])];
    const s = { id, cwd, pid: 0, state: 'starting', source: 'hub', startedAt: new Date().toISOString(),
      log: new EventLog(), pty: null, cols: 120, rows: 30 };
    s.pty = pty.spawn(file, args, {
      name: 'xterm-256color', cols: s.cols, rows: s.rows, cwd,
      env: { ...scrubEnv(process.env), ...this.extraEnv },
    });
    s.pid = s.pty.pid;
    this.#map.set(id, s);
    this.#persist();
    // coalesce PTY output into one term event per 25 ms
    let buf = '', timer = null;
    const flush = () => {
      timer = null;
      if (buf) s.log.append('term', { data: Buffer.from(buf, 'utf8').toString('base64') });
      buf = '';
    };
    s.pty.onData((d) => {
      if (s.state === 'starting') this.setState(s, 'running');
      buf += d;
      timer ??= setTimeout(flush, 25);
    });
    s.pty.onExit(() => {
      clearTimeout(timer);
      flush();
      this.setState(s, 'exited');
    });
    return s;
  }

  setState(s, state) {
    s.state = state;
    s.log.append('state', { state });
    this.#persist();
  }

  get(id) { return this.#map.get(id); }

  list() {
    const live = [...this.#map.values()].map(({ id, cwd, pid, state, source, startedAt }) => ({ id, cwd, pid, state, source, startedAt }));
    const ids = new Set(live.map((s) => s.id));
    return [...this.prior.filter((p) => !ids.has(p.id)), ...live];
  }

  input(id, text) {
    const s = this.get(id);
    if (!s || s.state === 'exited') return;
    s.pty.write('\x1b[200~' + text + '\x1b[201~');
    setTimeout(() => { try { s.pty.write('\r'); } catch {} }, 80);
  }

  keys(id, data) {
    const s = this.get(id);
    if (s && s.state !== 'exited') s.pty.write(data);
  }

  resize(id, cols, rows) {
    const s = this.get(id);
    if (!s || s.state === 'exited') return;
    s.cols = clamp(cols, 20, 500);
    s.rows = clamp(rows, 5, 200);
    s.pty.resize(s.cols, s.rows);
  }

  async nudge(id) {
    const s = this.get(id);
    if (!s || s.state === 'exited') return;
    const { cols, rows } = s;
    s.pty.resize(cols, rows + 1);
    await sleep(50);
    if (s.state !== 'exited') s.pty.resize(cols, rows);
  }

  killAll() {
    for (const s of this.#map.values()) { try { s.pty.kill(); } catch {} }
  }
}
