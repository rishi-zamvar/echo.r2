import fs from 'node:fs';
import path from 'node:path';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const short = (s) => String(s).replace(/\s*\n\s*/g, ' ').slice(0, 80);

// D-20: whitelist; everything unknown is dropped (T-01-19)
export function parseLine(o) {
  const c = o?.message?.content;
  if (o?.type === 'user') {
    if (o.isMeta) return [];
    if (typeof c === 'string') return /^<(local-command|command-name)/.test(c) ? [] : [{ role: 'user', text: c }];
    if (Array.isArray(c)) return c.filter((b) => b?.type === 'text' && typeof b.text === 'string').map((b) => ({ role: 'user', text: b.text }));
    return [];
  }
  if (o?.type === 'assistant' && Array.isArray(c)) {
    const out = [];
    for (const b of c) {
      if (b?.type === 'text' && typeof b.text === 'string') out.push({ role: 'assistant', text: b.text });
      else if (b?.type === 'tool_use' && typeof b.name === 'string') {
        const i = b.input ?? {};
        const arg = [i.command, i.file_path, i.pattern, i.description, i.prompt].find((x) => typeof x === 'string' && x) ?? '';
        out.push({ role: 'assistant', tool: b.name, text: short(`${b.name}: ${arg}`) });
      }
    }
    return out;
  }
  return [];
}

export class Tailer {
  #off = 0;
  #rest = Buffer.alloc(0);
  #w; #t;
  constructor(file, onLine) { this.file = file; this.onLine = onLine; }

  poll() {
    let fd;
    try {
      fd = fs.openSync(this.file, 'r');
      const size = fs.fstatSync(fd).size;
      if (size < this.#off) { this.#off = 0; this.#rest = Buffer.alloc(0); }
      if (size === this.#off) return;
      const buf = Buffer.alloc(size - this.#off);
      const n = fs.readSync(fd, buf, 0, buf.length, this.#off);
      this.#off += n;
      let data = Buffer.concat([this.#rest, buf.subarray(0, n)]);
      let nl;
      while ((nl = data.indexOf(0x0a)) >= 0) { // split in Buffer space so multibyte chars survive
        const line = data.subarray(0, nl).toString('utf8');
        data = data.subarray(nl + 1);
        if (!line.trim()) continue;
        let obj;
        try { obj = JSON.parse(line); } catch { continue; }
        try { this.onLine(obj); } catch {}
      }
      this.#rest = Buffer.from(data);
    } catch {} finally { if (fd !== undefined) try { fs.closeSync(fd); } catch {} }
  }

  start() {
    this.poll();
    try { this.#w = fs.watch(this.file, () => this.poll()); this.#w.on('error', () => {}); } catch {}
    this.#t = setInterval(() => this.poll(), 1000);
    this.#t.unref();
    return this;
  }

  stop() { this.poll(); clearInterval(this.#t); this.#w?.close(); }
}

// D-06: never reverse-encode cwd; scan project dirs for the id
export function findTranscript(projectsDir, id) {
  if (!UUID.test(id)) return null;
  try {
    for (const d of fs.readdirSync(projectsDir)) {
      const f = path.join(projectsDir, d, `${id}.jsonl`);
      if (fs.existsSync(f)) return f;
    }
  } catch {}
  return null;
}

export const labelFor = (e) => ({ cli: 'Terminal', 'sdk-ts': 'Even Terminal/SDK', 'sdk-cli': 'claude -p', 'claude-desktop': 'Desktop' })[e] ?? 'Other';

function edge(file, size, head) {
  const n = Math.min(size, 65536);
  const buf = Buffer.alloc(n);
  const fd = fs.openSync(file, 'r');
  try { fs.readSync(fd, buf, 0, n, head ? 0 : size - n); } finally { fs.closeSync(fd); }
  return buf.toString('utf8').split('\n').map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}

export function discoverExternal(projectsDir, { ownedIds = new Set(), maxAgeMs = 30 * 60 * 1000, liveIds = new Set() } = {}) {
  const out = [];
  let dirs = [];
  try { dirs = fs.readdirSync(projectsDir); } catch { return out; }
  for (const d of dirs) {
    let files = [];
    try { files = fs.readdirSync(path.join(projectsDir, d)); } catch { continue; }
    for (const name of files) {
      const id = name.slice(0, -6);
      if (!name.endsWith('.jsonl') || !UUID.test(id) || ownedIds.has(id)) continue;
      const file = path.join(projectsDir, d, name);
      try {
        const st = fs.statSync(file);
        if (Date.now() - st.mtimeMs > maxAgeMs && !liveIds.has(id)) continue;
        const first = edge(file, st.size, true).find((o) => o.entrypoint);
        const last = edge(file, st.size, false);
        const t = last.findLast((o) => o.type === 'ai-title' && o.aiTitle) ?? last.findLast((o) => o.type === 'last-prompt' && o.lastPrompt);
        out.push({ id, transcriptPath: file, cwd: first?.cwd ?? '', label: labelFor(first?.entrypoint), title: t?.aiTitle ?? t?.lastPrompt ?? '', mtimeMs: st.mtimeMs });
      } catch {}
    }
  }
  return out;
}

// undocumented registry (research Pattern 7); mtime is the fallback
export function liveSessionIds(claudeHome) {
  const ids = new Set();
  try {
    const dir = path.join(claudeHome, 'sessions');
    for (const n of fs.readdirSync(dir)) {
      try {
        const j = JSON.parse(fs.readFileSync(path.join(dir, n), 'utf8'));
        process.kill(j.pid, 0);
        if (typeof j.sessionId === 'string') ids.add(j.sessionId);
      } catch {}
    }
  } catch {}
  return ids;
}
