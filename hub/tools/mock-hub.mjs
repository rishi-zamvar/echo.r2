// Deterministic loopback mock hub for app UI tests. Fixture data only; no network beyond 127.0.0.1.
// Usage: node hub/tools/mock-hub.mjs [port=8799]
import http from 'node:http';
import fs from 'node:fs';
import { WebSocketServer } from 'ws';
import { parseLine } from '../transcript.js';

const PORT = Number(process.argv[2] ?? 8799);
const TOKEN = 'mock-token';
const EPOCH = 'mock-epoch';
const ID = (n) => `aaaaaaaa-0000-4000-8000-00000000000${n}`;
const T0 = '2026-11-12T10:00:00.000Z';

const sessions = [
  { id: ID(1), cwd: '/Users/mock/api', pid: 4101, state: 'running', source: 'hub', startedAt: T0, title: 'Auth middleware', summary: 'Refactor the auth middleware', noise: false, lastActivity: '2026-11-12T11:59:00.000Z' },
  { id: ID(2), cwd: '/Users/mock/web', pid: 0, state: 'stopped', source: 'hub', startedAt: T0, title: 'Landing page', summary: 'Fix the landing page hero layout', noise: false, lastActivity: '2026-11-12T09:00:00.000Z' },
  { id: ID(3), cwd: '/Users/mock/g2', pid: 0, state: 'external', source: 'external', startedAt: T0, label: 'Even Terminal/SDK', entrypoint: 'sdk-ts', summary: 'Brainstorm the glasses switcher', noise: false, lastActivity: '2026-11-12T11:30:00.000Z' },
  { id: ID(4), cwd: '/Users/mock/cli', pid: 0, state: 'external', source: 'external', startedAt: T0, label: 'Terminal', entrypoint: 'cli', summary: 'Write the release notes', noise: false, lastActivity: '2026-11-12T11:00:00.000Z' },
  { id: ID(5), cwd: '/tmp', pid: 0, state: 'external', source: 'external', startedAt: T0, label: 'Terminal', entrypoint: 'sdk-cli', summary: 'Ping pong reply', noise: true, lastActivity: '2026-11-12T08:00:00.000Z' },
  { id: ID(6), cwd: '/tmp', pid: 0, state: 'done', source: 'hub', startedAt: T0, summary: 'one-off question', noise: true, lastActivity: '2026-11-01T08:00:00.000Z' },
];
const byId = (id) => sessions.find((s) => s.id === id);

const history = fs.readFileSync(new URL('../fixtures/transcript-sample.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean)
  .flatMap((l) => { try { return parseLine(JSON.parse(l)); } catch { return []; } })
  .map((m, i) => ({ i, ...m }));

let scenario = { autoPair: 'ok', pushTest: 'envError' };
const reqLog = [];
const extra = new Map(); // id -> chat lines appended by `input` frames
const linesFor = (id) => [...history, ...(extra.get(id) ?? [])];

const send = (res, code, body) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
const readBody = (req) => new Promise((r) => { let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => { try { r(JSON.parse(b || '{}')); } catch { r({}); } }); });
const authed = (req) => req.headers.authorization === `Bearer ${TOKEN}`;

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;
  reqLog.push(`${req.method} ${p}`); if (reqLog.length > 100) reqLog.shift();
  const body = req.method === 'POST' ? await readBody(req) : {};

  if (p === '/__scenario' && req.method === 'POST') { scenario = { ...scenario, ...body }; return send(res, 200, scenario); }
  if (p === '/__requests') return send(res, 200, reqLog.slice(0, -1));
  if (p === '/health') {
    return send(res, 200, {
      ok: true, protocol: 1, version: '0.0.0-mock', gitSha: 'mock', uptime: 1, os: 'mock', hubName: 'mock-hub', epoch: EPOCH,
      claude: { ok: true, version: '0.0.0' }, push: 'ready',
      pushLastError: scenario.pushTest === 'envError' ? { status: 403, reason: 'BadEnvironmentKeyInToken', message: 'Push key is limited to one environment.', at: T0 } : null,
    });
  }
  if (p === '/pair/auto' && req.method === 'POST') {
    return scenario.autoPair === 'deny' ? send(res, 403, { error: 'auto_pair_denied' }) : send(res, 201, { token: TOKEN, deviceId: 'mock-device' });
  }
  if (p === '/pair' && req.method === 'POST') {
    return body.code === 'ABCD2345' ? send(res, 201, { token: TOKEN, deviceId: 'mock-device' }) : send(res, 403, { error: 'bad_code' });
  }
  if (!authed(req)) return send(res, 401, { error: 'unauthorized' });

  if (p === '/sessions' && req.method === 'GET') return send(res, 200, { epoch: EPOCH, sessions });
  let m;
  if ((m = p.match(/^\/sessions\/([^/]+)\/history$/)) && req.method === 'GET') {
    if (!byId(m[1])) return send(res, 404, { error: 'not_found' });
    const all = linesFor(m[1]);
    const limit = Math.min(500, Math.max(1, Number(url.searchParams.get('limit')) || 200));
    const bf = url.searchParams.get('before');
    const end = bf === null ? all.length : Math.min(all.length, Math.max(0, Number(bf)));
    const start = Math.max(0, end - limit);
    return send(res, 200, { id: m[1], lines: all.slice(start, end), before: start > 0 ? start : null });
  }
  if ((m = p.match(/^\/sessions\/([^/]+)\/(takeover|resume)$/)) && req.method === 'POST') {
    const s = byId(m[1]);
    if (!s) return send(res, 404, { error: 'not_found' });
    if (s.entrypoint === 'sdk-ts') return send(res, 409, { error: 'even_terminal' });
    if (s.id === ID(4)) { Object.assign(s, { source: 'hub', state: 'running', pid: 4104 }); }
    return send(res, 200, { ok: true, id: s.id });
  }
  if ((m = p.match(/^\/sessions\/([^/]+)\/stop$/)) && req.method === 'POST') {
    const s = byId(m[1]); if (s) s.state = 'stopped';
    return send(res, 200, { ok: true });
  }
  if (p === '/devices/push' && req.method === 'POST') return send(res, 200, { ok: true });
  if (p === '/devices/push/test' && req.method === 'POST') {
    const token = 'abcd1234';
    return send(res, 200, { sent: 1, results: [scenario.pushTest === 'envError'
      ? { token, status: 403, reason: 'BadEnvironmentKeyInToken', message: 'Push key is limited to one environment. In Apple Developer > Keys, set it to Sandbox & Production.' }
      : { token, status: 200 }] });
  }
  send(res, 404, { error: 'not_found' });
});

const wss = new WebSocketServer({ noServer: true });
server.on('upgrade', (req, sock, head) => {
  const url = new URL(req.url, 'http://x');
  const m = url.pathname.match(/^\/sessions\/([^/]+)\/stream$/);
  wss.handleUpgrade(req, sock, head, (ws) => {
    const s = m && byId(m[1]);
    const authOk = authed(req) || url.searchParams.get('token') === TOKEN;
    if (!authOk || !s || s.source !== 'hub' || s.state === 'stopped' || s.state === 'done') return ws.close(4404);
    let seq = 0;
    const emit = (o) => ws.readyState === 1 && ws.send(JSON.stringify({ v: 1, seq: ++seq, ...o }));
    ws.send(JSON.stringify({ v: 1, type: 'hello', id: s.id, epoch: EPOCH, seq, state: 'running' }));
    for (const l of linesFor(s.id)) emit({ kind: 'chat', role: l.role, text: l.text, ...(l.tool ? { tool: l.tool } : {}), i: l.i });
    emit({ kind: 'state', state: 'running' });
    ws.on('message', (raw) => {
      let f; try { f = JSON.parse(raw.toString()); } catch { return; }
      if (f.type !== 'input' || typeof f.text !== 'string') return;
      const arr = extra.get(s.id) ?? []; extra.set(s.id, arr);
      const u = { i: history.length + arr.length, role: 'user', text: f.text }; arr.push(u);
      emit({ kind: 'chat', role: 'user', text: u.text, i: u.i });
      setTimeout(() => {
        const a = { i: history.length + arr.length, role: 'assistant', text: `echo: ${f.text}` }; arr.push(a);
        emit({ kind: 'chat', role: 'assistant', text: a.text, i: a.i });
        emit({ kind: 'state', state: 'done' });
      }, 600);
    });
  });
});

server.listen(PORT, '127.0.0.1', () => console.log(`mock-hub on 127.0.0.1:${PORT}`));
process.on('SIGTERM', () => process.exit(0));
