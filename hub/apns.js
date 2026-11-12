import http2 from 'node:http2';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const b64u = (x) => Buffer.from(x).toString('base64url');

export function makeJwt(cfg, iat) {
  const data = `${b64u(JSON.stringify({ alg: 'ES256', kid: cfg.keyId }))}.${b64u(JSON.stringify({ iss: cfg.teamId, iat }))}`;
  const sig = crypto.sign('sha256', Buffer.from(data), { key: cfg.key, dsaEncoding: 'ieee-p1363' });
  return `${data}.${sig.toString('base64url')}`;
}

// first line only, cut to n chars with an ellipsis
const clip = (s, n) => {
  const l = String(s ?? '').split('\n')[0].trim();
  return l.length > n ? l.slice(0, n - 1) + '…' : l;
};

export function alertText(kind, s) {
  const title = clip(s.title || path.basename(s.cwd ?? '') || 'session', 60);
  const body = kind === 'done' ? clip(s.lastStop, 140) || 'finished'
    : kind === 'waiting' ? clip(s.lastMessage, 140) || 'needs you'
      : `exited (code ${s.exitCode ?? '?'})`;
  return { title, body };
}

export function apnsRequest({ token, env, bundleId, sessionId, title, body }) {
  const headers = { ':method': 'POST', ':path': `/3/device/${token}`, 'apns-topic': bundleId, 'apns-push-type': 'alert', 'apns-priority': '10' };
  if (sessionId) headers['apns-collapse-id'] = sessionId;
  const payload = { aps: { alert: { title: clip(title, 60), body: clip(body, 140) }, sound: 'default', 'thread-id': sessionId ?? 'hub' } };
  if (sessionId) payload.sessionId = sessionId;
  return { host: env === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com', headers, payload };
}

export function http2Send() {
  const sessions = new Map();
  const session = (host) => {
    let s = sessions.get(host);
    if (s && !s.closed && !s.destroyed) return s;
    s = http2.connect(host);
    const drop = () => { if (sessions.get(host) === s) sessions.delete(host); };
    s.on('goaway', drop); s.on('close', drop); s.on('error', drop);
    s.unref();
    sessions.set(host, s);
    return s;
  };
  const send = ({ host, headers, payload }) => new Promise((resolve, reject) => {
    let req;
    try { req = session(host).request(headers); } catch (e) { return reject(e); }
    let status = 0;
    let buf = '';
    req.setTimeout(10000, () => { req.close(http2.constants.NGHTTP2_CANCEL); reject(new Error('timeout')); });
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (c) => { buf += c; });
    req.on('end', () => { let reason; try { reason = JSON.parse(buf).reason; } catch {} resolve({ status, reason }); });
    req.on('error', reject);
    req.end(JSON.stringify(payload));
  });
  send.close = () => { for (const s of sessions.values()) s.close(); sessions.clear(); };
  return send;
}

export class Push {
  constructor({ apns = {}, dataDir = '.', devices, send, now = Date.now, cooldownMs = 10000 }) {
    this.devices = devices; this.now = now; this.cooldownMs = cooldownMs;
    this.cfg = apns;
    this.jwt = null; this.jwtAt = 0; this.key = null;
    this.status = 'unconfigured';
    if (apns.keyId && apns.teamId && apns.bundleId) {
      const file = apns.keyPath || path.join(dataDir, `AuthKey_${apns.keyId}.p8`);
      try {
        if (process.platform !== 'win32' && fs.statSync(file).mode & 0o077) { fs.chmodSync(file, 0o600); console.log('apns key chmod 600'); }
        this.key = fs.readFileSync(file, 'utf8');
        this.status = 'ready';
        this.send = send ?? http2Send();
      } catch (e) { console.log(`apns disabled: key unreadable (${e.code ?? 'error'})`); }
    } else console.log('apns disabled: not configured');
  }

  auth() {
    const t = this.now();
    if (!this.jwt || t - this.jwtAt > 45 * 60000) { this.jwt = makeJwt({ keyId: this.cfg.keyId, teamId: this.cfg.teamId, key: this.key }, Math.floor(t / 1000)); this.jwtAt = t; }
    return this.jwt;
  }

  async toTokens(targets, msg) {
    if (this.status !== 'ready') return null;
    return Promise.all(targets.map(async ({ token, env }) => {
      const req = apnsRequest({ token, env, bundleId: this.cfg.bundleId, ...msg });
      req.headers.authorization = `bearer ${this.auth()}`;
      const once = () => this.send(req).catch(() => null);
      let r = await once();
      if (!r || r.status >= 500) r = await once(); // retry exactly once
      const out = { token: token.slice(0, 8), status: r ? r.status : 0 };
      if (r?.reason) out.reason = r.reason;
      else if (!r) out.reason = 'conn';
      if (out.status !== 200) console.log(`apns ${out.token} ${out.status} ${out.reason ?? ''}`);
      if (r && (r.status === 410 || (r.status === 400 && (r.reason === 'BadDeviceToken' || r.reason === 'Unregistered')))) {
        this.devices.dropPush(token);
        console.log(`apns dropped token ${out.token}`);
      }
      return out;
    }));
  }

  broadcast(title, body) { return this.toTokens(this.devices.pushTargets(), { title, body }); }
  toDevice(deviceId, title, body) { return this.toTokens(this.devices.pushTargets(deviceId), { title, body }); }
  // 04-02 adds the per-session cooldown on top
  alert(s, kind) { return this.toTokens(this.devices.pushTargets(), { ...alertText(kind, s), sessionId: s.id }); }
  close() { this.send?.close?.(); }
}
