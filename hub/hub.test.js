import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import WebSocket from 'ws';
import { startHub } from './server.js';
import { EventLog } from './eventlog.js';
import { scrubEnv, transition } from './sessions.js';

const fake = path.join(import.meta.dirname, 'fixtures', 'fake-claude.mjs');
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'echo-'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(pred, ms = 5000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (pred()) return; await sleep(25); }
  throw new Error('waitFor timeout');
}
function frames(ws) {
  const out = [];
  ws.on('message', (m) => out.push(JSON.parse(m.toString())));
  return out;
}
const open = (ws) => new Promise((res, rej) => { ws.on('open', res); ws.on('error', rej); });

const hub = await startHub({ port: 0, claudeCmd: [process.execPath, fake], dataDir: tmp(), killOnClose: true, hookPort: 0 });
const base = `http://127.0.0.1:${hub.port}`;
const wsBase = `ws://127.0.0.1:${hub.port}`;
after(() => hub.close());

async function create() {
  const r = await fetch(`${base}/sessions`, {
    method: 'POST', body: JSON.stringify({ cwd: tmp() }),
  });
  assert.equal(r.status, 201);
  return (await r.json()).id;
}

test('scrubEnv', () => {
  const e = scrubEnv({ CLAUDECODE: '1', CLAUDE_CODE_CHILD_SESSION: '1', X: undefined, PATH: '/b', ANTHROPIC_API_KEY: 'k' });
  assert.deepEqual(e, { PATH: '/b', ANTHROPIC_API_KEY: 'k' });
});

test('EventLog reset', () => {
  const l = new EventLog({ maxBytes: 200 });
  for (let i = 0; i < 50; i++) l.append('term', { data: 'x' });
  const r = l.since(0);
  assert.equal(r.reset, true);
  assert.equal(r.events[0].seq, l.floor);
  assert.equal(l.since(l.floor - 1).reset, false);
});

test('loopback bind', () => {
  assert.equal(hub.server.address().address, '127.0.0.1');
});

test('session outlives client', async () => {
  const id = await create();
  const ws = new WebSocket(`${wsBase}/sessions/${id}/stream`);
  const f = frames(ws);
  await open(ws);
  await waitFor(() => f[0]?.type === 'hello' &&
    f.some((x) => x.kind === 'term' && Buffer.from(x.data, 'base64').toString().includes('READY')));
  ws.close();
  const s = hub.sessions.get(id);
  const seq0 = s.log.seq;
  await sleep(300);
  const list = await (await fetch(`${base}/sessions`)).json();
  assert.ok(list.sessions.some((x) => x.id === id));
  assert.ok(s.log.seq > seq0);
});

test('replay since, no duplicates', async () => {
  const id = await create();
  const ws = new WebSocket(`${wsBase}/sessions/${id}/stream?since=0`);
  const f1 = frames(ws);
  await open(ws);
  await waitFor(() => f1.filter((x) => x.kind).length >= 3);
  const k = f1.filter((x) => x.kind).at(-1).seq;
  ws.close();
  await sleep(300);
  const ws2 = new WebSocket(`${wsBase}/sessions/${id}/stream?since=${k}&epoch=${hub.epoch}`);
  const f2 = frames(ws2);
  await open(ws2);
  await waitFor(() => f2.filter((x) => x.kind).length >= 2);
  const ev1 = f1.filter((x) => x.kind).map((x) => x.seq);
  const ev2 = f2.filter((x) => x.kind).map((x) => x.seq);
  assert.equal(ev2[0], k + 1);
  const all = [...ev1.filter((s) => s <= k), ...ev2];
  assert.equal(new Set(all).size, all.length);
  assert.deepEqual(all, [...all].sort((a, b) => a - b));
  assert.ok(!f2.some((x) => x.type === 'reset'));
  ws2.close();
});

test('epoch mismatch resets', async () => {
  const id = await create();
  const ws = new WebSocket(`${wsBase}/sessions/${id}/stream?since=1&epoch=bogus`);
  const f = frames(ws);
  await open(ws);
  await waitFor(() => f.length >= 2);
  assert.equal(f[0].type, 'hello');
  assert.equal(f[1].type, 'reset');
  ws.close();
});

// ---- plan 02: live state ----
const hook = (body, secret = hub.secret) => fetch(`http://127.0.0.1:${hub.hookPort}/hook`, {
  method: 'POST', headers: secret ? { 'x-echo-secret': secret } : {},
  body: typeof body === 'string' ? body : JSON.stringify(body),
});
const st = (id) => hub.sessions.get(id).state;
const ev = (id, kind, state) => hub.sessions.get(id).log.since(0).events.some((e) => e.kind === kind && e.state === state);
const hp = (id, name, extra = {}) => ({ session_id: id, hook_event_name: name, transcript_path: '/t.jsonl', cwd: '/', ...extra });

test('transition table', () => {
  const rows = [
    ['starting', 'data', 'running'], ['running', 'data', 'running'], ['waiting', 'data', 'waiting'], ['done', 'data', 'done'],
    ['starting', 'input', 'running'], ['running', 'input', 'running'], ['waiting', 'input', 'running'], ['done', 'input', 'running'],
    ['starting', 'stop', 'done'], ['running', 'stop', 'done'], ['waiting', 'stop', 'done'], ['done', 'stop', 'done'],
    ['starting', 'notification', 'waiting'], ['running', 'notification', 'waiting'], ['done', 'notification', 'waiting'], ['waiting', 'notification', 'waiting'],
    ['starting', 'exit', 'exited'], ['running', 'exit', 'exited'], ['waiting', 'exit', 'exited'], ['done', 'exit', 'exited'],
    ['starting', 'boot', 'stopped'], ['running', 'boot', 'stopped'], ['waiting', 'boot', 'stopped'], ['done', 'boot', 'stopped'],
  ];
  for (const [a, sig, b] of rows) assert.equal(transition(a, sig), b, `${a}+${sig}`);
  for (const sig of ['data', 'input', 'stop', 'notification', 'exit', 'boot']) {
    for (const abs of ['exited', 'stopped', 'external']) assert.equal(transition(abs, sig), abs, `${abs}+${sig}`);
  }
});

test('hook drives state', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  assert.equal((await hook(hp(id, 'Stop'))).status, 200);
  await sleep(500);
  assert.notEqual(st(id), 'done');
  await sleep(1500);
  assert.equal(st(id), 'done');
  assert.ok(ev(id, 'state', 'done'));
});

test('input cancels stop debounce', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  await hook(hp(id, 'Stop'));
  const ws = new WebSocket(`${wsBase}/sessions/${id}/stream`);
  await open(ws);
  await sleep(200);
  ws.send(JSON.stringify({ type: 'input', text: 'x' }));
  await sleep(2000);
  assert.equal(st(id), 'running');
  ws.close();
});

test('notification -> waiting', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  await hook(hp(id, 'Notification', { message: 'm', notification_type: 'permission_prompt' }));
  await waitFor(() => st(id) === 'waiting', 500);
});

test('agent_id ignored', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  await hook(hp(id, 'Stop', { agent_id: 'a1' }));
  await sleep(2000);
  assert.equal(st(id), 'running');
});

test('bad secret and bad json', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  assert.equal((await hook(hp(id, 'Notification'), null)).status, 403);
  assert.equal((await hook(hp(id, 'Notification'), 'wrong')).status, 403);
  assert.equal((await hook('{nope')).status, 200);
  await sleep(200);
  assert.equal(st(id), 'running');
});

test('unknown session_id -> external', async () => {
  const id = crypto.randomUUID();
  await hook(hp(id, 'Stop'));
  await waitFor(() => hub.sessions.get(id));
  const list = await (await fetch(`${base}/sessions`)).json();
  const x = list.sessions.find((s) => s.id === id);
  assert.equal(x.state, 'external');
  assert.equal(x.source, 'external');
});

test('pty exit -> exited', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  process.kill(hub.sessions.get(id).pid, 'SIGKILL');
  await waitFor(() => st(id) === 'exited');
});

test('boot marks stopped, spawn args', async () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, 'sessions.json'), JSON.stringify([{ id: 'a'.repeat(8), state: 'running', source: 'hub' }]));
  const h = await startHub({ port: 0, hookPort: 0, claudeCmd: [process.execPath, fake], dataDir: dir, killOnClose: true });
  try {
    const l = h.sessions.list();
    assert.equal(l.find((s) => s.id === 'a'.repeat(8)).state, 'stopped');
    const hooks = fs.readFileSync(path.join(dir, 'hub-hooks.json'), 'utf8');
    assert.ok(hooks.includes('"type":"http"') || hooks.includes('"type": "http"'));
    assert.ok(hooks.includes('$ECHO_SECRET'));
    assert.ok(!hooks.includes(h.secret));
    const r = await fetch(`http://127.0.0.1:${h.port}/sessions`, { method: 'POST', body: JSON.stringify({ cwd: tmp() }) });
    const { id } = await r.json();
    await waitFor(() => h.sessions.get(id).log.since(0).events.some((e) => e.kind === 'term' && Buffer.from(e.data, 'base64').toString().includes(`READY session=${id}`)));
  } finally { h.close(); }
});
