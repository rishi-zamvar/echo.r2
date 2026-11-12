import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { load, save } from './store.js';

const run = promisify(execFile);

export function defaultTailscale() {
  if (process.env.ECHO_TAILSCALE) return [process.env.ECHO_TAILSCALE];
  if (process.platform === 'darwin') {
    return [fs.existsSync('/usr/local/bin/tailscale') ? '/usr/local/bin/tailscale' : '/Applications/Tailscale.app/Contents/MacOS/Tailscale'];
  }
  if (process.platform === 'win32') return ['C:\\Program Files\\Tailscale\\tailscale.exe'];
  return ['tailscale'];
}

// CGNAT 100.64.0.0/10
export function isTailnetIp(ip) {
  if (!net.isIPv4(ip)) return false;
  const [a, b] = ip.split('.').map(Number);
  return a === 100 && b >= 64 && b <= 127;
}

export async function tailnetIp(cmd, { allowLoopback = false } = {}) {
  try {
    const { stdout } = await run(cmd[0], [...cmd.slice(1), 'ip', '-4'], { timeout: 3000 });
    const ip = stdout.split('\n')[0].trim();
    return isTailnetIp(ip) || (allowLoopback && ip === '127.0.0.1') ? ip : null;
  } catch { return null; }
}

export function makeWhois({ cmd, ttlMs = 60000 }) {
  const cache = new Map();
  // detail: {login, node} or null (tagged, errors, missing); node = stable id for the deny list
  async function detail(remoteAddress) {
    const ip = String(remoteAddress ?? '').replace(/^::ffff:/, '');
    if (!net.isIP(ip)) return null;
    const hit = cache.get(ip);
    if (hit && hit.exp > Date.now()) return hit.d;
    try {
      const { stdout } = await run(cmd[0], [...cmd.slice(1), 'whois', '--json', ip], { timeout: 3000, maxBuffer: 1 << 20 });
      const j = JSON.parse(stdout);
      const login = j?.UserProfile?.LoginName;
      if (typeof login !== 'string' || !login || login === 'tagged-devices') return null;
      if (Array.isArray(j?.Node?.Tags) && j.Node.Tags.length) return null;
      const d = { login, node: j?.Node?.StableID || j?.Node?.ID || j?.Node?.Name || null };
      if (cache.size > 100) cache.clear();
      cache.set(ip, { d, exp: Date.now() + ttlMs });
      return d;
    } catch { return null; }
  }
  const whois = async (ip) => (await detail(ip))?.login ?? null;
  whois.detail = detail;
  return whois;
}

export function loadConfig(dataDir) {
  const file = path.join(dataDir, 'config.json');
  const cfg = load(file, {});
  let dirty = false;
  if (!cfg.hookSecret) { cfg.hookSecret = crypto.randomBytes(16).toString('hex'); dirty = true; }
  if (!cfg.roots) {
    const home = os.homedir();
    cfg.roots = process.platform === 'win32' ? [path.join(process.env.USERPROFILE || home, 'Projects')] : [path.join(home, 'Documents', 'Projects'), home];
    dirty = true;
  }
  if (dirty) saveConfig(dataDir, cfg);
  return cfg;
}

export function saveConfig(dataDir, cfg) {
  save(path.join(dataDir, 'config.json'), cfg, { mode: 0o600 });
}

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const sha = (s) => crypto.createHash('sha256').update(s).digest();
const same = (a, b) => a.length === b.length && crypto.timingSafeEqual(a, b);

// one live pairing code at a time; 5 wrong attempts burn it
export class Pairing {
  constructor({ ttlMs = 300000, now = Date.now } = {}) { this.ttlMs = ttlMs; this.now = now; this.live = null; }
  create(name) {
    let code = '';
    for (let i = 0; i < 8; i++) code += ALPHABET[crypto.randomInt(32)];
    this.live = { code, name, attempts: 0, expiresAt: this.now() + this.ttlMs };
    return { code, expiresAt: this.live.expiresAt };
  }
  redeem(input) {
    const l = this.live;
    if (!l) return null;
    if (this.now() >= l.expiresAt) { this.live = null; return null; }
    const norm = String(input ?? '').toUpperCase().replace(/[\s-]/g, '').replace(/O/g, '0').replace(/[IL]/g, '1');
    if (same(Buffer.from(norm), Buffer.from(l.code))) { this.live = null; return { name: l.name }; }
    if (++l.attempts >= 5) this.live = null;
    return null;
  }
}

// devices.json: [{id, name, hash(sha256 hex), createdAt, lastSeen}]
export class Devices {
  constructor(file) { this.file = file; this.items = load(file, []); this.saved = 0; }
  persist() { save(this.file, this.items, { mode: 0o600 }); this.saved = Date.now(); }
  add(name, autoNode) {
    const token = crypto.randomBytes(32).toString('base64url');
    const id = crypto.randomUUID();
    this.items.push({ id, name, hash: sha(token).toString('hex'), createdAt: new Date().toISOString(), lastSeen: null, ...(autoNode ? { autoNode } : {}) });
    this.persist();
    return { token, deviceId: id };
  }
  verify(token) {
    const h = sha(String(token));
    let hit = null;
    for (const d of this.items) if (same(h, Buffer.from(d.hash, 'hex'))) hit = d; // no early exit
    if (!hit) return null;
    hit.lastSeen = new Date().toISOString();
    if (Date.now() - this.saved > 60000) this.persist();
    return hit;
  }
  revoke(idOrName) {
    let m = this.items.filter((d) => d.id === idOrName);
    if (!m.length) m = this.items.filter((d) => d.name === idOrName);
    if (m.length > 1) throw Object.assign(new Error('ambiguous'), { code: 'ambiguous' });
    if (m.length) { this.items = this.items.filter((d) => d !== m[0]); this.persist(); }
    return m.map((d) => d.id);
  }
  setPush(deviceId, token, env) {
    for (const d of this.items) if (d.push?.token === token) delete d.push;
    const d = this.items.find((x) => x.id === deviceId);
    if (!d) return;
    d.push = { token, env, at: new Date().toISOString() };
    this.persist();
  }
  dropPush(token) {
    const d = this.items.find((x) => x.push?.token === token);
    if (d) { delete d.push; this.persist(); }
  }
  pushTargets(deviceId) {
    return this.items.filter((d) => d.push && (!deviceId || d.id === deviceId)).map((d) => ({ deviceId: d.id, token: d.push.token, env: d.push.env }));
  }
  list() { return this.items.map(({ id, name, createdAt, lastSeen, push }) => ({ id, name, createdAt, lastSeen, push: Boolean(push) })); }
}

// D-10: cwd must resolve (symlinks included) inside a configured root
export function inRoots(cwd, roots) {
  if (typeof cwd !== 'string' || !path.isAbsolute(cwd)) return false;
  const fold = (p) => (process.platform === 'win32' ? p.toLowerCase() : p);
  let real;
  try { real = fold(fs.realpathSync(cwd)); } catch { return false; }
  for (const root of roots ?? []) {
    let rr;
    try { rr = fold(fs.realpathSync(root)); } catch { continue; }
    const rel = path.relative(rr, real);
    if (rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel))) return true;
  }
  return false;
}

// D-11: picker data
export function listRoots(roots) {
  return (roots ?? []).map((root) => {
    let dirs = [];
    try {
      dirs = fs.readdirSync(root, { withFileTypes: true })
        .filter((e) => e.isDirectory() && !e.name.startsWith('.')).map((e) => e.name).sort().slice(0, 200);
    } catch {}
    return { root, dirs };
  });
}
