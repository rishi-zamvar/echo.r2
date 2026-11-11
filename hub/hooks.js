import http from 'node:http';
import fs from 'node:fs';
import crypto from 'node:crypto';

const MAX_BODY = 1 << 20;

export function writeHooksFile(file, hookPort) {
  const entry = [{ hooks: [{
    type: 'http', url: `http://127.0.0.1:${hookPort}/hook`,
    headers: { 'X-Echo-Secret': '$ECHO_SECRET' }, allowedEnvVars: ['ECHO_SECRET'], timeout: 5,
  }] }];
  fs.writeFileSync(file, JSON.stringify({ hooks: { Stop: entry, Notification: entry } }));
}

export function startHookServer({ port = +process.env.ECHO_HOOK_PORT || 8791, secret, extSecret, onHook, onExtHook }) {
  const want = Buffer.from(secret);
  const wantExt = Buffer.from(String(extSecret ?? ''));
  const server = http.createServer((req, res) => {
    const ext = req.method === 'POST' && extSecret && req.url.startsWith('/hook/ext/');
    if (req.method !== 'POST' || (req.url !== '/hook' && !ext)) { res.writeHead(404); return res.end(); }
    const got = Buffer.from(ext ? req.url.slice('/hook/ext/'.length) : String(req.headers['x-echo-secret'] ?? ''));
    const want_ = ext ? wantExt : want;
    if (got.length !== want_.length || !crypto.timingSafeEqual(got, want_)) { res.writeHead(403); return res.end(); }
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) { res.writeHead(413); res.end(); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (size > MAX_BODY) return;
      res.writeHead(200); res.end(); // D-16: answer first, parse after
      queueMicrotask(() => {
        try { (ext ? onExtHook : onHook)(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch {}
      });
    });
  });
  return new Promise((resolve, reject) => {
    server.once('error', (e) => reject(e.code === 'EADDRINUSE' ? new Error(`hook port ${port} in use`) : e));
    server.listen(port, '127.0.0.1', () => resolve(server));
  });
}
