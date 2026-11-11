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
  return async function whois(remoteAddress) {
    const ip = String(remoteAddress ?? '').replace(/^::ffff:/, '');
    if (!net.isIP(ip)) return null;
    const hit = cache.get(ip);
    if (hit && hit.exp > Date.now()) return hit.login;
    try {
      const { stdout } = await run(cmd[0], [...cmd.slice(1), 'whois', '--json', ip], { timeout: 3000, maxBuffer: 1 << 20 });
      const login = JSON.parse(stdout)?.UserProfile?.LoginName;
      if (typeof login !== 'string' || !login || login === 'tagged-devices') return null;
      if (cache.size > 100) cache.clear();
      cache.set(ip, { login, exp: Date.now() + ttlMs });
      return login;
    } catch { return null; }
  };
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
