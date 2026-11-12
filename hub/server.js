import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { WebSocketServer } from 'ws';
import { Sessions, resolveClaude } from './sessions.js';
import { discoverExternal, liveSessionIds, readHistory, findTranscript } from './transcript.js';
import { startHookServer, writeHooksFile } from './hooks.js';
import { makeWhois, tailnetIp, loadConfig, saveConfig, defaultTailscale, Pairing, Devices, inRoots, listRoots } from './auth.js';
import { execFileSync } from 'node:child_process';
import { Push } from './apns.js';

const version = JSON.parse(fs.readFileSync(new URL('./package.json', import.meta.url), 'utf8')).version;
const MAX_BODY = 1 << 20;

export async function startHub({
  port = +process.env.ECHO_PORT || 8790,
  host = '127.0.0.1',
  claudeCmd = resolveClaude(),
  dataDir = process.env.ECHO_DATA_DIR || path.join(os.homedir(), '.echo-hub'),
  hookPort = +process.env.ECHO_HOOK_PORT || 8791,
  killOnClose = false,
  spawnEnv = {},
  stallMs,
  claudeHome = process.env.ECHO_CLAUDE_HOME || path.join(os.homedir(), '.claude'),
  tailscale = defaultTailscale(),
  tailnetPort = port,
  retryMs = 1000,
  allowLoopbackTailnet = false, // test-only
  whoisTtlMs = 60000,
  apnsSend, // test-only stub; default http2
  apnsCooldownMs, // test-only
} = {}) {
  if (host !== '127.0.0.1') throw new Error('loopback listener binds 127.0.0.1 only');
  const epoch = crypto.randomUUID();
  const secret = crypto.randomBytes(16).toString('hex'); // per boot, child env only (D-15)
  fs.mkdirSync(dataDir, { recursive: true });
  const config = loadConfig(dataDir);
  const whois = makeWhois({ cmd: tailscale, ttlMs: whoisTtlMs });
  const pairing = new Pairing();
  const devices = new Devices(path.join(dataDir, 'devices.json'));
  let gitSha = 'unknown';
  try { gitSha = execFileSync('git', ['rev-parse', '--short=7', 'HEAD'], { cwd: import.meta.dirname, encoding: 'utf8', timeout: 3000, stdio: ['ignore', 'pipe', 'ignore'] }).trim() || 'unknown'; } catch {}
  const push = new Push({ apns: config.apns ?? {}, dataDir, devices, send: apnsSend, cooldownMs: apnsCooldownMs });
  const hooksFile = path.join(dataDir, 'hub-hooks.json');
  const projectsDir = path.join(claudeHome, 'projects');
  const sessions = new Sessions({ claudeCmd, epoch, dataDir, projectsDir, extraArgs: () => ['--settings', hooksFile], extraEnv: { ...spawnEnv, ECHO_SECRET: secret }, onAlert: (s, kind) => push.alert(s, kind), stallMs });
  const hookServer = await startHookServer({ port: hookPort, secret, extSecret: config.hookSecret,
    onHook: (p) => sessions.hook(p),
    onExtHook: (p) => { if (p && typeof p.session_id === 'string' && sessions.ownedIds().has(p.session_id)) return; sessions.hook(p); } });
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

  const health = () => ({ ok: true, protocol: 1, version, gitSha, uptime: process.uptime(), os: process.platform, hubName: os.hostname(), epoch, claude, push: push.status });
  const deny = (sock, line) => { sock.end(`HTTP/1.1 ${line}\r\nConnection: close\r\n\r\n`); };

  // returns true if request may proceed to loopback routing; otherwise has responded
  const loopbackOk = (req) => {
    const p = server.address()?.port;
    return !req.headers.origin && (req.headers.host === `127.0.0.1:${p}` || req.headers.host === `localhost:${p}`);
  };
  // returns true if tailnet peer is the owner (or no owner pinned yet)
  const tailnetOk = async (req) => {
    const login = await whois(req.socket.remoteAddress);
    return !!login && (!config.owner || login === config.owner);
  };

  const makeHandler = ({ tailnet }) => async (req, res) => {
    try {
      const url = new URL(req.url, 'http://x');
      if (tailnet) {
        const login = await whois(req.socket.remoteAddress);
        if (!login || (config.owner && login !== config.owner)) return json(res, 403, { error: 'forbidden' });
        if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, health());
        if (req.method === 'POST' && url.pathname === '/pair') return await pair(req, res, login);
        const dev = bearerDevice(req);
        if (!dev) return json(res, 401, { error: 'unauthorized' });
        return await routes(req, res, url, dev);
      }
      if (!loopbackOk(req)) return json(res, 403, { error: 'forbidden' });
      if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, health());
      if (url.pathname.startsWith('/admin/')) return await adminRoutes(req, res, url);
      return await routes(req, res, url, null);
    } catch {
      if (!res.headersSent) json(res, 500, { error: 'internal' });
    }
  };

  // Authorization header only; never the query string
  const bearerDevice = (req) => {
    const m = /^Bearer (\S+)$/.exec(req.headers.authorization ?? '');
    return m ? devices.verify(m[1]) : null;
  };
  const parseBody = async (req) => {
    try { const b = JSON.parse(await readBody(req)); return b && typeof b === 'object' ? b : null; } catch { return null; }
  };
  const trimName = (v) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, 64) : undefined);

  async function pair(req, res, login) {
    const body = await parseBody(req);
    const got = body ? pairing.redeem(body.code) : null;
    if (!got) return json(res, 403, { error: 'bad_code' });
    const name = got.name || trimName(body.deviceName) || 'device';
    const out = devices.add(name);
    if (!config.owner) { config.owner = login; saveConfig(dataDir, config); }
    console.log(`paired ${name}`);
    json(res, 201, out);
  }

  // loopback only: dispatched solely by the non-tailnet handler
  async function adminRoutes(req, res, url) {
    if (req.method === 'POST' && url.pathname === '/admin/pair-code') {
      const body = (await parseBody(req)) ?? {};
      pairing.create(trimName(body.name));
      return json(res, 200, { code: pairing.live.code, expiresIn: Math.round(pairing.ttlMs / 1000) });
    }
    if (req.method === 'GET' && url.pathname === '/admin/devices') return json(res, 200, { devices: devices.list() });
    if (req.method === 'POST' && url.pathname === '/admin/revoke') {
      const body = await parseBody(req);
      if (!body || typeof body.id !== 'string') return json(res, 400, { error: 'bad_json' });
      const name = devices.items.find((d) => d.id === body.id || d.name === body.id)?.name;
      let revoked;
      try { revoked = devices.revoke(body.id); } catch { return json(res, 409, { error: 'ambiguous' }); }
      if (!revoked.length) return json(res, 404, { error: 'not_found' });
      for (const ws of wss.clients) if (revoked.includes(ws.deviceId)) ws.close(4401, 'revoked');
      console.log(`revoked ${name}`);
      return json(res, 200, { revoked });
    }
    if (req.method === 'POST' && url.pathname === '/admin/test-push') {
      if (push.status !== 'ready') return json(res, 503, { error: 'push_unconfigured' });
      const results = await push.broadcast('echo', 'test push · ' + os.hostname());
      return json(res, 200, { sent: results.length, results });
    }
    json(res, 404, { error: 'not_found' });
  }

  async function routes(req, res, url, dev) {
    try {
      if (req.method === 'POST' && url.pathname === '/devices/push') {
        if (!dev) return json(res, 400, { error: 'no_device' });
        const b = await parseBody(req);
        if (!b || typeof b.token !== 'string' || !/^[0-9a-fA-F]{64,200}$/.test(b.token) || !['sandbox', 'production'].includes(b.env)) return json(res, 400, { error: 'bad_push' });
        devices.setPush(dev.id, b.token.toLowerCase(), b.env);
        console.log(`push token ${dev.name} ${b.env}`);
        return json(res, 200, { ok: true });
      }
      if (req.method === 'POST' && url.pathname === '/devices/push/test') {
        if (!dev) return json(res, 400, { error: 'no_device' });
        if (push.status !== 'ready') return json(res, 503, { error: 'push_unconfigured' });
        if (!devices.pushTargets(dev.id).length) return json(res, 404, { error: 'no_token' });
        const results = await push.toDevice(dev.id, 'echo', 'test push · ' + os.hostname());
        return json(res, 200, { sent: results.length, results });
      }
      if (req.method === 'GET' && url.pathname === '/sessions') {
        return json(res, 200, { epoch, sessions: sessions.list() });
      }
      if (req.method === 'GET' && url.pathname === '/sessions/roots') return json(res, 200, { roots: listRoots(config.roots) });
      if (req.method === 'POST' && url.pathname === '/sessions') {
        let body;
        try { body = JSON.parse(await readBody(req)); } catch (e) {
          return e.status === 413 ? json(res, 413, { error: 'too_large' }) : json(res, 400, { error: 'bad_json' });
        }
        if (!body || typeof body !== 'object') return json(res, 400, { error: 'bad_json' });
        if (body.prompt !== undefined && (typeof body.prompt !== 'string' || body.prompt.length > 10000)) {
          return json(res, 400, { error: 'bad_prompt' });
        }
        if (!inRoots(body.cwd, config.roots)) return json(res, 400, { error: 'bad_cwd' });
        if (!claude.ok) return json(res, 503, { error: 'claude_unavailable' });
        try {
          const s = sessions.start({ cwd: body.cwd, prompt: body.prompt });
          return json(res, 201, { id: s.id });
        } catch (e) {
          if (e.code === 'bad_cwd') return json(res, 400, { error: 'bad_cwd' });
          return json(res, 500, { error: 'spawn_failed' });
        }
      }
      const m = req.method === 'POST' && url.pathname.match(/^\/sessions\/([0-9a-f-]{36})\/stop$/);
      if (m) {
        try { await sessions.stop(m[1]); return json(res, 200, { ok: true }); } catch (e) {
          return json(res, { not_found: 404, read_only: 409, not_running: 409 }[e.code] ?? 500, { error: e.code ?? 'internal' });
        }
      }
      const rm = req.method === 'POST' && url.pathname.match(/^\/sessions\/([0-9a-f-]{36})\/(resume|takeover)$/);
      if (rm) {
        const [, id, what] = rm;
        if (!claude.ok) return json(res, 503, { error: 'claude_unavailable' });
        const cwd = sessions.get(id)?.cwd ?? sessions.prior.find((p) => p.id === id)?.cwd;
        if (cwd === undefined) return json(res, 404, { error: 'not_found' });
        if (!inRoots(cwd, config.roots)) return json(res, 400, { error: 'bad_cwd' });
        try {
          const liveIds = liveSessionIds(claudeHome);
          if (what === 'resume') sessions.resume(id, { liveIds }); else sessions.takeover(id, liveIds);
          console.log(`${what === 'resume' ? 'resumed' : 'took over'} ${id.slice(0, 8)}`);
          return json(res, 200, { ok: true, id });
        } catch (e) {
          if (e.code === 'even_terminal' || e.code === 'live_elsewhere') console.log(`refused ${what} ${id.slice(0, 8)} ${e.code}`);
          return json(res, { not_found: 404, not_resumable: 409, busy: 409, bad_cwd: 400, even_terminal: 409, live_elsewhere: 409 }[e.code] ?? 500, { error: e.code ?? 'internal' });
        }
      }
      const hm = req.method === 'GET' && url.pathname.match(/^\/sessions\/([0-9a-f-]{36})\/history$/);
      if (hm) { // D-06: no transcript content is ever logged here
        const id = hm[1];
        const file = sessions.get(id)?.transcriptPath ?? findTranscript(projectsDir, id);
        const known = file || sessions.get(id) || sessions.prior.find((p) => p.id === id);
        if (!known) return json(res, 404, { error: 'not_found' });
        const lp = url.searchParams.get('limit'), bp = url.searchParams.get('before');
        const limit = lp == null ? 200 : Math.min(500, Math.max(1, Math.floor(+lp) || 200));
        if (bp !== null && !/^\d+$/.test(bp)) return json(res, 400, { error: 'bad_cursor' });
        let all = [];
        if (file) {
          try { all = readHistory(file); } catch (e) { return e.code === 'too_large' ? json(res, 413, { error: 'too_large' }) : json(res, 200, { id, lines: [], before: null }); }
        }
        const end = bp === null ? all.length : Math.min(+bp, all.length);
        const start = Math.max(0, end - limit);
        return json(res, 200, { id, lines: all.slice(start, end), before: start > 0 ? start : null });
      }
      json(res, 404, { error: 'not_found' });
    } catch {
      if (!res.headersSent) json(res, 500, { error: 'internal' });
    }
  }
  const server = http.createServer(makeHandler({ tailnet: false }));

  const wss = new WebSocketServer({ noServer: true, maxPayload: 1 << 20 });
  const makeUpgrade = ({ tailnet }) => async (req, sock, head) => {
    sock.on('error', () => {});
    if (tailnet) {
      if (!(await tailnetOk(req))) return deny(sock, '403 Forbidden');
    } else if (!loopbackOk(req)) return deny(sock, '403 Forbidden');
    const device = tailnet ? bearerDevice(req) : null;
    if (tailnet && !device) return deny(sock, '401 Unauthorized');
    const u = new URL(req.url, 'http://x');
    const m = u.pathname.match(/^\/sessions\/([0-9a-f-]{36})\/stream$/);
    if (!m) return sock.destroy();
    wss.handleUpgrade(req, sock, head, (ws) => {
      if (device) ws.deviceId = device.id;
      attach(ws, m[1], u.searchParams);
    });
  };
  server.on('upgrade', makeUpgrade({ tailnet: false }));

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
      let p;
      if (f.type === 'input' && typeof f.text === 'string') p = () => sessions.input(id, f.text);
      else if (f.type === 'keys' && typeof f.data === 'string') p = () => sessions.keys(id, f.data);
      else if (f.type === 'interrupt') p = () => sessions.interrupt(id);
      else if (f.type === 'resize' && Number.isFinite(+f.cols) && Number.isFinite(+f.rows)) return sessions.resize(id, f.cols, f.rows);
      else return bad();
      p().catch((e) => send({ v: 1, type: 'error', code: e.code ?? 'internal' }));
    });
  }

  const scan = () => {
    const found = discoverExternal(projectsDir, { ownedIds: sessions.ownedIds(), liveIds: liveSessionIds(claudeHome) });
    for (const f of found) sessions.addExternal(f);
    sessions.pruneExternals(new Set(found.map((f) => f.id)));
  };
  scan();
  const scanTimer = setInterval(scan, 5000);

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
  console.log(`echo hub ${version} ${gitSha} loopback 127.0.0.1:${actualPort}`);

  // tailnet listener: bind to `tailscale ip -4`, retry with backoff until it appears
  let tailnetServer = null;
  let closing = false;
  let resolveReady;
  let announced = false;
  const tailnetReady = new Promise((r) => { resolveReady = r; });
  (async () => {
    let delay = retryMs;
    let lastState = '';
    while (!closing) {
      const ip = await tailnetIp(tailscale, { allowLoopback: allowLoopbackTailnet });
      if (ip && !closing) {
        const t = http.createServer(makeHandler({ tailnet: true }));
        t.on('upgrade', makeUpgrade({ tailnet: true }));
        const ok = await new Promise((resolve) => {
          t.once('error', () => resolve(false));
          t.listen(tailnetPort, ip, () => resolve(true));
        });
        if (ok) {
          tailnetServer = t;
          const gone = new Promise((resolve) => { t.once('error', resolve); t.once('close', resolve); });
          if (lastState !== 'up') console.log(`tailnet listening ${ip}:${t.address().port}`);
          lastState = 'up';
          resolveReady(t.address().port);
          if (!announced) { // D-06: first bind per process only
            announced = true;
            push.broadcast('echo hub', `online · ${os.hostname()} · ${gitSha}`).catch((e) => console.log('hub-started push failed', e.message));
          }
          delay = retryMs;
          await gone;
          tailnetServer = null;
          if (closing) break;
          console.log('tailnet listener lost');
          lastState = '';
          continue;
        }
        t.close();
      }
      if (lastState !== 'waiting') console.log('tailnet waiting');
      lastState = 'waiting';
      await new Promise((r) => setTimeout(r, delay));
      delay = Math.min(delay * 2, 30000);
    }
  })();

  return {
    epoch, port: actualPort, hookPort: actualHookPort, secret, sessions, server, config, tailnetReady,
    get tailnetServer() { return tailnetServer; },
    close() {
      closing = true;
      tailnetServer?.close();
      tailnetServer?.closeAllConnections?.();
      clearInterval(hb);
      clearInterval(scanTimer);
      sessions.close();
      push.close();
      for (const ws of wss.clients) ws.terminate();
      if (killOnClose) sessions.killAll();
      server.close();
      hookServer.close();
      hookServer.closeAllConnections?.();
      server.closeAllConnections?.();
    },
  };
}

export function openLog(file, { maxBytes = 5 * 1024 * 1024 } = {}) {
  const rotate = () => { try { if (fs.statSync(file).size > maxBytes) fs.renameSync(file, file + '.1'); } catch {} };
  rotate();
  const timer = setInterval(rotate, 3600000);
  timer.unref();
  const log = (...args) => { try { fs.appendFileSync(file, `${new Date().toISOString()} ${args.join(' ')}\n`, { mode: 0o600 }); } catch {} };
  log.close = () => clearInterval(timer);
  return log;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const dir = process.env.ECHO_DATA_DIR || path.join(os.homedir(), '.echo-hub');
  fs.mkdirSync(dir, { recursive: true });
  const log = openLog(path.join(dir, 'hub.log'));
  console.log = console.error = log;
  process.on('uncaughtException', (e) => { log(e.message, e.stack); process.exit(1); });
  startHub().catch((e) => {
    console.error(e.code === 'EADDRINUSE' ? `port ${process.env.ECHO_PORT || 8790} in use` : e.message);
    process.exit(1);
  });
}
