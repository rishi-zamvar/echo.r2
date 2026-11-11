import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { WebSocketServer } from 'ws';
import { Sessions, resolveClaude } from './sessions.js';
import { startHookServer, writeHooksFile } from './hooks.js';

const version = JSON.parse(fs.readFileSync(new URL('./package.json', import.meta.url), 'utf8')).version;
const MAX_BODY = 1 << 20;

export async function startHub({
  port = +process.env.ECHO_PORT || 8790,
  host = '127.0.0.1',
  claudeCmd = resolveClaude(),
  dataDir = process.env.ECHO_DATA_DIR || path.join(os.homedir(), '.echo-hub'),
  hookPort = +process.env.ECHO_HOOK_PORT || 8791,
  killOnClose = false,
} = {}) {
  if (host !== '127.0.0.1') throw new Error('hub binds to 127.0.0.1 only (Phase 1)'); // T-01-01
  const epoch = crypto.randomUUID();
  const secret = crypto.randomBytes(16).toString('hex'); // per boot, child env only (D-15)
  fs.mkdirSync(dataDir, { recursive: true });
  const hooksFile = path.join(dataDir, 'hub-hooks.json');
  const sessions = new Sessions({ claudeCmd, epoch, dataDir, extraArgs: () => ['--settings', hooksFile], extraEnv: { ECHO_SECRET: secret } });
  const hookServer = await startHookServer({ port: hookPort, secret, onHook: (p) => sessions.hook(p) });
  const actualHookPort = hookServer.address().port;
  writeHooksFile(hooksFile, actualHookPort);
  const claude = await sessions.selfTest();
  console.log(claude.ok ? `claude ok ${claude.version}` : 'claude FAIL');

  const json = (res, code, obj) => {
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(obj));
  };

  function readBody(req) {
    return new Promise((resolve, reject) => {
      let size = 0;
      const chunks = [];
      req.on('data', (c) => {
        size += c.length;
        if (size > MAX_BODY) { reject(Object.assign(new Error('too large'), { status: 413 })); req.destroy(); return; }
        chunks.push(c);
      });
      req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      req.on('error', reject);
    });
  }

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://x');
      if (req.method === 'GET' && url.pathname === '/health') {
        return json(res, 200, { ok: true, protocol: 1, version, epoch, uptime: process.uptime(), claude });
      }
      if (req.method === 'GET' && url.pathname === '/sessions') {
        return json(res, 200, { epoch, sessions: sessions.list() });
      }
      if (req.method === 'POST' && url.pathname === '/sessions') {
        let body;
        try { body = JSON.parse(await readBody(req)); } catch (e) {
          return e.status === 413 ? json(res, 413, { error: 'too_large' }) : json(res, 400, { error: 'bad_json' });
        }
        if (!body || typeof body !== 'object') return json(res, 400, { error: 'bad_json' });
        if (body.prompt !== undefined && (typeof body.prompt !== 'string' || body.prompt.length > 10000)) {
          return json(res, 400, { error: 'bad_prompt' });
        }
        if (!claude.ok) return json(res, 503, { error: 'claude_unavailable' });
        try {
          const s = sessions.start({ cwd: body.cwd, prompt: body.prompt });
          return json(res, 201, { id: s.id });
        } catch (e) {
          if (e.code === 'bad_cwd') return json(res, 400, { error: 'bad_cwd' });
          return json(res, 500, { error: 'spawn_failed' });
        }
      }
      json(res, 404, { error: 'not_found' });
    } catch {
      if (!res.headersSent) json(res, 500, { error: 'internal' });
    }
  });

  const wss = new WebSocketServer({ noServer: true, maxPayload: 1 << 20 });
  server.on('upgrade', (req, sock, head) => {
    const u = new URL(req.url, 'http://x');
    const m = u.pathname.match(/^\/sessions\/([0-9a-f-]{36})\/stream$/);
    if (!m) return sock.destroy();
    wss.handleUpgrade(req, sock, head, (ws) => attach(ws, m[1], u.searchParams));
  });

  function attach(ws, id, q) {
    const s = sessions.get(id);
    if (!s) return ws.close(4404, 'unknown session');
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    const send = (f) => {
      if (ws.bufferedAmount > 1 << 20) return ws.terminate(); // client reconnects with since=
      ws.send(JSON.stringify(f));
    };
    // Pitfall 5: snapshot replay + subscribe in the same synchronous block
    const sinceParam = q.get('since');
    const epochParam = q.get('epoch');
    send({ v: 1, type: 'hello', id, epoch, seq: s.log.seq, state: s.state });
    const r = s.log.since(sinceParam == null ? 0 : +sinceParam || 0);
    const reset = r.reset || (epochParam != null && epochParam !== epoch);
    if (reset) send({ v: 1, type: 'reset', epoch });
    for (const e of reset && !r.reset ? s.log.since(-Infinity).events : r.events) send(e);
    const unsub = s.log.subscribe(send);
    if (reset) sessions.nudge(id);
    ws.on('close', unsub);
    ws.on('message', (raw) => {
      let f;
      try { f = JSON.parse(raw.toString()); } catch { f = null; }
      const bad = () => send({ v: 1, type: 'error', code: 'bad_frame' });
      if (!f || typeof f !== 'object') return bad();
      if (f.type === 'input' && typeof f.text === 'string') sessions.input(id, f.text);
      else if (f.type === 'keys' && typeof f.data === 'string') sessions.keys(id, f.data);
      else if (f.type === 'resize' && Number.isFinite(+f.cols) && Number.isFinite(+f.rows)) sessions.resize(id, f.cols, f.rows);
      else bad();
    });
  }

  const hb = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) { ws.terminate(); continue; }
      ws.isAlive = false;
      ws.ping();
    }
  }, 20000);

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, resolve);
  });
  const actualPort = server.address().port;

  return {
    epoch, port: actualPort, hookPort: actualHookPort, secret, sessions, server,
    close() {
      clearInterval(hb);
      for (const ws of wss.clients) ws.terminate();
      if (killOnClose) sessions.killAll();
      server.close();
      hookServer.close();
      hookServer.closeAllConnections?.();
      server.closeAllConnections?.();
    },
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  startHub().then((h) => console.log(`echo hub listening 127.0.0.1:${h.port}`)).catch((e) => {
    console.error(e.code === 'EADDRINUSE' ? `port ${process.env.ECHO_PORT || 8790} in use` : e.message);
    process.exit(1);
  });
}
