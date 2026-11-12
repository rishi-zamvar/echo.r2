import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import WebSocket from 'ws';
import { spawn } from 'node:child_process';
import http from 'node:http';
import { startHub, openLog } from './server.js';
import { makeWhois, inRoots } from './auth.js';
import { EventLog } from './eventlog.js';
import { scrubEnv, transition } from './sessions.js';

const fake = path.join(import.meta.dirname, 'fixtures', 'fake-claude.mjs');
const rdir = () => { const d = tmp(); fs.writeFileSync(path.join(d, 'config.json'), JSON.stringify({ roots: [fs.realpathSync(os.tmpdir())] })); return d; };
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

const fakeTs = path.join(import.meta.dirname, 'fixtures', 'fake-tailscale.mjs');
const tsState = path.join(tmp(), 'ts.json');
const OWNER = { UserProfile: { LoginName: 'owner@example.com' } };
const setTs = (patch) => fs.writeFileSync(tsState, JSON.stringify({ ...(fs.existsSync(tsState) ? JSON.parse(fs.readFileSync(tsState, 'utf8')) : {}), ...patch }));
setTs({ ip: '127.0.0.1', whois: OWNER, exit: 0 });
process.env.FAKE_TS_STATE = tsState;
const hubDir = tmp();
fs.writeFileSync(path.join(hubDir, 'config.json'), JSON.stringify({ owner: 'owner@example.com', roots: [fs.realpathSync(os.tmpdir())] }));
const hub = await startHub({ port: 0, claudeCmd: [process.execPath, fake], dataDir: hubDir, killOnClose: true, hookPort: 0,
  tailscale: [process.execPath, fakeTs], tailnetPort: 0, allowLoopbackTailnet: true, whoisTtlMs: 0 });
const tb = `http://127.0.0.1:${await hub.tailnetReady}`;
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
  const dir = rdir();
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

// ---- plan 03: steer and stop ----
const posix = { skip: process.platform === 'win32' };
const termText = (id) => hub.sessions.get(id).log.since(0).events
  .filter((e) => e.kind === 'term').map((e) => Buffer.from(e.data, 'base64').toString()).join('');
const gone = (pid) => { try { process.kill(pid, 0); return false; } catch (e) { return e.code === 'ESRCH'; } };
const errFrame = async (id, frame) => {
  const ws = new WebSocket(`${wsBase}/sessions/${id}/stream`);
  const f = frames(ws);
  await open(ws);
  ws.send(JSON.stringify(frame));
  await sleep(300);
  ws.close();
  return f.find((x) => x.type === 'error');
};

test('interrupt reaches pty', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  const ws = new WebSocket(`${wsBase}/sessions/${id}/stream`);
  await open(ws);
  ws.send(JSON.stringify({ type: 'interrupt' }));
  await waitFor(() => termText(id).includes('^C-RECEIVED'), 1000);
  ws.close();
});

test('stop kills tree', posix, async () => {
  const h = await startHub({ port: 0, hookPort: 0, claudeCmd: [process.execPath, fake], dataDir: rdir(), killOnClose: true, spawnEnv: { FAKE_GRANDCHILD: '1' } });
  try {
    const r = await fetch(`http://127.0.0.1:${h.port}/sessions`, { method: 'POST', body: JSON.stringify({ cwd: tmp() }) });
    const { id } = await r.json();
    const s = h.sessions.get(id);
    const text = () => s.log.since(0).events.filter((e) => e.kind === 'term').map((e) => Buffer.from(e.data, 'base64').toString()).join('');
    await waitFor(() => /GRANDCHILD \d+/.test(text()));
    const gpid = +text().match(/GRANDCHILD (\d+)/)[1];
    const res = await fetch(`http://127.0.0.1:${h.port}/sessions/${id}/stop`, { method: 'POST' });
    assert.equal(res.status, 200);
    await waitFor(() => gone(s.pid) && gone(gpid), 3000);
    assert.equal(s.state, 'exited');
  } finally { h.close(); }
});

test('two writers serialized', async () => {
  const id = await create();
  await waitFor(() => st(id) === 'running');
  const a = new WebSocket(`${wsBase}/sessions/${id}/stream`);
  const b = new WebSocket(`${wsBase}/sessions/${id}/stream`);
  await Promise.all([open(a), open(b)]);
  a.send(JSON.stringify({ type: 'input', text: 'A'.repeat(2000) }));
  b.send(JSON.stringify({ type: 'input', text: 'B'.repeat(2000) }));
  const got = () => termText(id).split('\r\n').filter((l) => l.startsWith('IN:')).map((l) => JSON.parse(l.slice(3))).join('');
  const pa = '\x1b[200~' + 'A'.repeat(2000) + '\x1b[201~\r';
  const pb = '\x1b[200~' + 'B'.repeat(2000) + '\x1b[201~\r';
  await waitFor(() => got().length >= pa.length + pb.length, 3000);
  assert.ok([pa + pb, pb + pa].includes(got()));
  a.close(); b.close();
});

test('external read-only', async () => {
  const id = crypto.randomUUID();
  await hook(hp(id, 'Stop'));
  await waitFor(() => hub.sessions.get(id));
  for (const f of [{ type: 'input', text: 'x' }, { type: 'keys', data: 'x' }, { type: 'interrupt' }]) {
    assert.equal((await errFrame(id, f))?.code, 'read_only');
  }
  assert.equal((await fetch(`${base}/sessions/${id}/stop`, { method: 'POST' })).status, 409);
});

test('boot sweep kills leftover', posix, async () => {
  const dir = tmp();
  const victim = spawn(process.execPath, [fake], { detached: true, stdio: 'ignore' });
  const bystander = spawn('sleep', ['30'], { detached: true, stdio: 'ignore' });
  after(() => { for (const c of [victim, bystander]) try { process.kill(c.pid, 'SIGKILL'); } catch {} });
  await sleep(300);
  fs.writeFileSync(path.join(dir, 'sessions.json'), JSON.stringify([
    { id: 'v'.repeat(8), pid: victim.pid, state: 'running', source: 'hub' },
    { id: 'b'.repeat(8), pid: bystander.pid, state: 'running', source: 'hub' },
  ]));
  const h = await startHub({ port: 0, hookPort: 0, claudeCmd: [process.execPath, fake], dataDir: dir, killOnClose: true });
  try {
    await waitFor(() => gone(victim.pid), 3000);
    const l = h.sessions.list();
    assert.equal(l.find((s) => s.id === 'v'.repeat(8)).state, 'stopped');
    assert.equal(l.find((s) => s.id === 'b'.repeat(8)).state, 'stopped');
    assert.equal(gone(bystander.pid), false);
  } finally { h.close(); }
});

// ---- plan 04: transcripts and external discovery ----
import { parseLine, Tailer, discoverExternal } from './transcript.js';
const fixture = fs.readFileSync(path.join(import.meta.dirname, 'fixtures', 'transcript-sample.jsonl'), 'utf8');
const lines = fixture.split('\n').filter(Boolean);

test('parser fixture', () => {
  const out = lines.flatMap((l) => parseLine(JSON.parse(l)));
  assert.equal(out.length, 4);
  assert.deepEqual(out[0], { role: 'user', text: 'list the files in this repo' });
  assert.deepEqual(out[1], { role: 'assistant', text: "I'll list the files." });
  assert.deepEqual(out[2], { role: 'assistant', tool: 'Bash', text: 'Bash: ls -la' });
  assert.ok(out[3].text.startsWith('There are 3 files') && out[3].text.includes('日本語'));
});

test('parser noise', () => {
  const u = (content, extra) => ({ type: 'user', message: { role: 'user', content }, ...extra });
  assert.deepEqual(parseLine(u('<command-name>/x</command-name>')), []);
  assert.deepEqual(parseLine(u('hi', { isMeta: true })), []);
  assert.deepEqual(parseLine(u('<local-command-stdout>x')), []);
});

test('tailer partial line', () => {
  const f = path.join(tmp(), 't.jsonl');
  const got = [];
  const line = Buffer.from(JSON.stringify({ a: '日本語' }) + '\n');
  const cut = line.indexOf(Buffer.from('日')) + 1; // mid-codepoint
  fs.writeFileSync(f, line.subarray(0, cut));
  const t = new Tailer(f, (o) => got.push(o));
  t.poll();
  assert.equal(got.length, 0);
  fs.appendFileSync(f, line.subarray(cut));
  t.poll();
  assert.deepEqual(got, [{ a: '日本語' }]);
});

const UA = 'aaaaaaaa-0000-4000-8000-00000000000a';
const UB = 'bbbbbbbb-0000-4000-8000-00000000000b';
const UC = 'cccccccc-0000-4000-8000-00000000000c';
function mkHome() {
  const home = tmp();
  const put = (proj, id, text) => {
    fs.mkdirSync(path.join(home, 'projects', proj), { recursive: true });
    const f = path.join(home, 'projects', proj, `${id}.jsonl`);
    fs.writeFileSync(f, text);
    return f;
  };
  return { home, put };
}

test('discovery', () => {
  const { home, put } = mkHome();
  put('-a', UA, fixture);
  put('-b', UB, fixture.replaceAll('"entrypoint":"cli"', '"entrypoint":"sdk-ts"') + JSON.stringify({ type: 'ai-title', aiTitle: 'Newest title' }) + '\n');
  const old = put('-c', UC, fixture);
  const t = (Date.now() - 2 * 3600e3) / 1000;
  fs.utimesSync(old, t, t);
  const dir = path.join(home, 'projects');
  const r = discoverExternal(dir, { ownedIds: new Set() });
  assert.deepEqual(r.map((x) => x.id).sort(), [UA, UB]);
  assert.equal(r.find((x) => x.id === UA).label, 'Terminal');
  const b = r.find((x) => x.id === UB);
  assert.equal(b.label, 'Even Terminal/SDK');
  assert.equal(b.title, 'Newest title');
  assert.equal(b.cwd, '/home/user/proj');
  assert.deepEqual(discoverExternal(dir, { ownedIds: new Set([UA]) }).map((x) => x.id), [UB]);
  assert.ok(discoverExternal(dir, { ownedIds: new Set(), liveIds: new Set([UC]) }).some((x) => x.id === UC));
});

test('external in hub', async () => {
  const { home, put } = mkHome();
  const f = put('-b', UB, fixture.replaceAll('"entrypoint":"cli"', '"entrypoint":"sdk-ts"'));
  const h = await startHub({ port: 0, hookPort: 0, claudeCmd: [process.execPath, fake], dataDir: tmp(), claudeHome: home, killOnClose: true });
  try {
    const l = (await (await fetch(`http://127.0.0.1:${h.port}/sessions`)).json()).sessions.find((s) => s.id === UB);
    assert.equal(l.state, 'external');
    assert.equal(l.source, 'external');
    assert.equal(l.label, 'Even Terminal/SDK');
    const ws = new WebSocket(`ws://127.0.0.1:${h.port}/sessions/${UB}/stream?since=0`);
    const fr = frames(ws);
    await open(ws);
    await waitFor(() => fr.filter((x) => x.kind === 'chat').length >= 4);
    fs.appendFileSync(f, JSON.stringify({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'appended!' }] } }) + '\n');
    await waitFor(() => fr.some((x) => x.kind === 'chat' && x.text === 'appended!'), 2500);
    ws.send(JSON.stringify({ type: 'input', text: 'x' }));
    await waitFor(() => fr.some((x) => x.type === 'error' && x.code === 'read_only'));
    ws.close();
  } finally { h.close(); }
});

test('hub session chat', async () => {
  const { home } = mkHome();
  const h = await startHub({ port: 0, hookPort: 0, claudeCmd: [process.execPath, fake], dataDir: rdir(), claudeHome: home, killOnClose: true });
  try {
    const r = await fetch(`http://127.0.0.1:${h.port}/sessions`, { method: 'POST', body: JSON.stringify({ cwd: tmp() }) });
    const { id } = await r.json();
    fs.mkdirSync(path.join(home, 'projects', '-x'), { recursive: true });
    fs.writeFileSync(path.join(home, 'projects', '-x', `${id}.jsonl`), lines[3] + '\n' + lines[6] + '\n');
    await waitFor(() => h.sessions.get(id).log.since(0).events.some((e) => e.kind === 'chat' && e.text === "I'll list the files."), 4000);
    assert.ok(!h.sessions.list().some((s) => s.id === id && s.source === 'external'));
  } finally { h.close(); }
});

// ---- phase 2 plan 01: tailnet / whois / health ----
const raw = (port, { method = 'GET', path: p = '/health', headers = {} } = {}) => new Promise((res, rej) => {
  const r = http.request({ host: '127.0.0.1', port, method, path: p, headers }, (m) => {
    let b = ''; m.on('data', (c) => { b += c; }); m.on('end', () => res({ status: m.statusCode, body: b }));
  });
  r.on('error', rej); r.end();
});
const tport = () => +new URL(tb).port;

test('health fields', async () => {
  for (const b of [base, tb]) {
    const h = await (await fetch(`${b}/health`)).json();
    assert.equal(h.ok, true); assert.equal(h.protocol, 1);
    assert.equal(typeof h.version, 'string');
    assert.match(h.gitSha, /^([0-9a-f]{7}|unknown)$/);
    assert.equal(typeof h.uptime, 'number'); assert.equal(h.os, process.platform);
    assert.equal(typeof h.hubName, 'string'); assert.ok(h.epoch); assert.ok(h.claude);
  }
});

test('whois fail closed', async () => {
  try {
    for (const patch of [{ exit: 1 }, { exit: 0, whois: 'not json' }, { exit: 0, whois: { Node: {} } },
      { exit: 0, whois: { UserProfile: { LoginName: 'intruder@example.com' } } }]) {
      setTs({ exit: 0, whois: OWNER, ...patch });
      assert.equal((await fetch(`${tb}/health`)).status, 403, JSON.stringify(patch));
    }
  } finally { setTs({ exit: 0, whois: OWNER }); }
  assert.equal((await fetch(`${tb}/health`)).status, 200);
});

test('whois rejects tagged', async () => {
  const w = makeWhois({ cmd: [process.execPath, fakeTs], ttlMs: 0 });
  try {
    for (const [who, want] of [[{ UserProfile: { LoginName: 'tagged-devices' }, Node: { Tags: ['tag:server'] } }, null],
      [{ Node: {} }, null], [{ UserProfile: { LoginName: '' } }, null], [OWNER, 'owner@example.com']]) {
      setTs({ whois: who });
      assert.equal(await w('::ffff:100.64.0.1'), want);
    }
  } finally { setTs({ whois: OWNER }); }
});

test('tailnet requires token', async () => {
  const r = await fetch(`${tb}/sessions`);
  assert.equal(r.status, 401);
  assert.deepEqual(await r.json(), { error: 'unauthorized' });
  const ws = new WebSocket(`${tb.replace('http', 'ws')}/sessions/${crypto.randomUUID()}/stream`);
  const outcome = await new Promise((res) => {
    ws.on('open', () => res('open'));
    ws.on('unexpected-response', (_q, m) => res(m.statusCode));
    ws.on('error', () => res('error'));
  });
  assert.notEqual(outcome, 'open');
});

test('loopback rejects foreign host', async () => {
  const bad = await raw(hub.port, { headers: { host: 'evil.example:80' } });
  assert.equal(bad.status, 403); assert.deepEqual(JSON.parse(bad.body), { error: 'forbidden' });
  assert.equal((await raw(hub.port, { headers: { host: `localhost:${hub.port}` } })).status, 200);
});

test('loopback rejects origin', async () => {
  const o = { origin: 'http://evil.example' };
  assert.equal((await raw(hub.port, { method: 'POST', path: '/sessions', headers: o })).status, 403);
  const ws = new WebSocket(`${wsBase}/sessions/${crypto.randomUUID()}/stream`, { headers: o });
  const outcome = await new Promise((res) => {
    ws.on('open', () => res('open'));
    ws.on('unexpected-response', (_q, m) => res(m.statusCode));
    ws.on('error', () => res('error'));
  });
  assert.notEqual(outcome, 'open');
});

test('bind addresses', () => {
  assert.equal(hub.server.address().address, '127.0.0.1');
  assert.equal(hub.tailnetServer.address().address, '127.0.0.1'); // fake ip
  for (const f of ['server.js', 'auth.js', 'hooks.js']) {
    const src = fs.readFileSync(path.join(import.meta.dirname, f), 'utf8');
    assert.ok(!src.includes('0.0.0.0'), f);
    assert.ok(!/['"]::['"]/.test(src), f);
  }
});

test('tailnet retry bind', async () => {
  const st = path.join(tmp(), 'ts.json');
  fs.writeFileSync(st, JSON.stringify({ ip: '', whois: OWNER, exit: 0 }));
  const prev = process.env.FAKE_TS_STATE;
  process.env.FAKE_TS_STATE = st;
  const h2 = await startHub({ port: 0, claudeCmd: [process.execPath, fake], dataDir: tmp(), hookPort: 0,
    tailscale: [process.execPath, fakeTs], tailnetPort: 0, allowLoopbackTailnet: true, retryMs: 20 });
  try {
    assert.equal((await fetch(`http://127.0.0.1:${h2.port}/health`)).status, 200);
    assert.equal(h2.tailnetServer, null);
    fs.writeFileSync(st, JSON.stringify({ ip: '127.0.0.1', whois: OWNER, exit: 0 }));
    const p = await Promise.race([h2.tailnetReady, sleep(2000).then(() => { throw new Error('no bind'); })]);
    // no owner configured on h2 yet; any valid non-tagged login is accepted
    assert.equal((await fetch(`http://127.0.0.1:${p}/health`)).status, 200);
  } finally { h2.close(); process.env.FAKE_TS_STATE = prev; }
});

// ---- phase 2 plan 02: pairing, bearer tokens, revoke ----
import { Pairing } from './auth.js';
const jpost = (url, body, headers = {}) => fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
const mintCode = async (b = base, name) => (await (await jpost(`${b}/admin/pair-code`, name ? { name } : {})).json()).code;
async function pairDevice(deviceName = 'x', b = base, t = tb) {
  const code = await mintCode(b);
  const r = await jpost(`${t}/pair`, { code, deviceName });
  assert.equal(r.status, 201);
  return r.json();
}
const bearer = (token) => ({ authorization: `Bearer ${token}` });
const wsOutcome = (url, headers) => new Promise((res) => {
  const ws = new WebSocket(url, { headers });
  ws.msgs = frames(ws);
  ws.on('open', () => res({ ws, outcome: 'open' }));
  ws.on('unexpected-response', (_q, m) => res({ ws, outcome: m.statusCode }));
  ws.on('error', () => res({ ws, outcome: 'error' }));
});

test('pair happy path', async () => {
  const r = await jpost(`${base}/admin/pair-code`, { name: 'test-phone' });
  assert.equal(r.status, 200);
  const { code, expiresIn } = await r.json();
  assert.match(code, /^[0-9A-HJKMNP-TV-Z]{8}$/);
  assert.equal(expiresIn, 300);
  const typed = (code.slice(0, 4) + '-' + code.slice(4)).toLowerCase();
  const p = await jpost(`${tb}/pair`, { code: typed, deviceName: 'x' });
  assert.equal(p.status, 201);
  const j = await p.json();
  assert.ok(j.token && j.deviceId);
  const again = await jpost(`${tb}/pair`, { code, deviceName: 'x' });
  assert.equal(again.status, 403);
  assert.deepEqual(await again.json(), { error: 'bad_code' });
});

test('bearer required', async () => {
  const { token, deviceId } = await pairDevice();
  assert.ok(deviceId);
  assert.equal((await fetch(`${tb}/sessions`, { headers: bearer(token) })).status, 200);
  const none = await fetch(`${tb}/sessions`);
  assert.equal(none.status, 401);
  assert.deepEqual(await none.json(), { error: 'unauthorized' });
  assert.equal((await fetch(`${tb}/sessions`, { headers: bearer('nope') })).status, 401);
  assert.equal((await fetch(`${tb}/sessions?token=${token}`)).status, 401);
  const id = await create();
  const wsUrl = `${tb.replace('http', 'ws')}/sessions/${id}/stream`;
  const ok = await wsOutcome(wsUrl, bearer(token));
  assert.equal(ok.outcome, 'open');
  await waitFor(() => ok.ws.msgs.length);
  assert.equal(ok.ws.msgs[0].type, 'hello');
  ok.ws.close();
  assert.equal((await wsOutcome(wsUrl, {})).outcome, 401);
});

test('pair limits', async () => {
  let code = await mintCode();
  for (let i = 0; i < 5; i++) {
    const wrong = code[0] === '2' ? '3' + code.slice(1) : '2' + code.slice(1);
    assert.equal((await jpost(`${tb}/pair`, { code: wrong })).status, 403);
  }
  assert.equal((await jpost(`${tb}/pair`, { code })).status, 403);
  const old = await mintCode();
  const fresh = await mintCode();
  assert.equal((await jpost(`${tb}/pair`, { code: old })).status, old === fresh ? 201 : 403);
  const p = new Pairing({ ttlMs: 50 });
  const c = p.create('n').code;
  await sleep(80);
  assert.equal(p.redeem(c), null);
});

test('devices file', posix, async () => {
  const { token } = await pairDevice();
  const f = path.join(hubDir, 'devices.json');
  const txt = fs.readFileSync(f, 'utf8');
  assert.ok(!txt.includes(token));
  assert.match(txt, /"hash": ?"[0-9a-f]{64}"/);
  assert.equal(fs.statSync(f).mode & 0o777, 0o600);
});

test('revoke closes access', async () => {
  const { token, deviceId } = await pairDevice('revokee');
  const list = await (await fetch(`${base}/admin/devices`)).json();
  const d = list.devices.find((x) => x.id === deviceId);
  assert.ok(d && !('hash' in d));
  const id = await create();
  const { ws, outcome } = await wsOutcome(`${tb.replace('http', 'ws')}/sessions/${id}/stream`, bearer(token));
  assert.equal(outcome, 'open');
  const closed = new Promise((res) => ws.on('close', (code) => res(code)));
  const r = await jpost(`${base}/admin/revoke`, { id: deviceId });
  assert.equal(r.status, 200);
  assert.deepEqual((await r.json()).revoked, [deviceId]);
  assert.equal(await closed, 4401);
  assert.equal((await fetch(`${tb}/sessions`, { headers: bearer(token) })).status, 401);
  assert.equal((await jpost(`${base}/admin/revoke`, { id: deviceId })).status, 404);
});

test('admin 404 on tailnet', async () => {
  const { token, deviceId } = await pairDevice();
  const h = bearer(token);
  assert.equal((await jpost(`${tb}/admin/pair-code`, {}, h)).status, 404);
  assert.equal((await fetch(`${tb}/admin/devices`, { headers: h })).status, 404);
  assert.equal((await jpost(`${tb}/admin/revoke`, { id: deviceId }, h)).status, 404);
  assert.equal((await fetch(`${tb}/sessions`, { headers: h })).status, 200);
});

test('owner captured at first pair', async () => {
  const st = path.join(tmp(), 'ts.json');
  const as = (login) => fs.writeFileSync(st, JSON.stringify({ ip: '127.0.0.1', whois: { UserProfile: { LoginName: login } }, exit: 0 }));
  as('first@example.com');
  const prev = process.env.FAKE_TS_STATE;
  process.env.FAKE_TS_STATE = st;
  const dir = tmp();
  const h2 = await startHub({ port: 0, claudeCmd: [process.execPath, fake], dataDir: dir, hookPort: 0,
    tailscale: [process.execPath, fakeTs], tailnetPort: 0, allowLoopbackTailnet: true, whoisTtlMs: 0 });
  try {
    const b2 = `http://127.0.0.1:${h2.port}`;
    const t2 = `http://127.0.0.1:${await h2.tailnetReady}`;
    await pairDevice('p', b2, t2);
    assert.equal(JSON.parse(fs.readFileSync(path.join(dir, 'config.json'), 'utf8')).owner, 'first@example.com');
    as('other@example.com');
    assert.equal((await fetch(`${t2}/health`)).status, 403);
  } finally { h2.close(); process.env.FAKE_TS_STATE = prev; }
});

// ---- phase 2 plan 03: allowlist, roots, ext hooks, log ----
const rootReal = fs.realpathSync(os.tmpdir());
test('cwd allowlist', async () => {
  const { token } = await pairDevice();
  const h = bearer(token);
  const bad = async (cwd, b = base, hh = {}) => {
    const r = await jpost(`${b}/sessions`, { cwd }, hh);
    assert.equal(r.status, 400);
    assert.equal((await r.json()).error, 'bad_cwd');
  };
  await bad(path.dirname(rootReal));
  await bad(path.join(tmp(), 'nope'));
  await bad(path.dirname(rootReal), tb, h);
  if (process.platform !== 'win32') {
    const d = tmp();
    fs.symlinkSync('/', path.join(d, 'esc'));
    await bad(path.join(d, 'esc'));
    await bad(path.join(d, 'esc'), tb, h);
  }
  const ok = await jpost(`${tb}/sessions`, { cwd: tmp() }, h);
  assert.equal(ok.status, 201);
  // prefix sibling
  const evil = rootReal + '-evil';
  fs.mkdirSync(evil, { recursive: true });
  try {
    assert.equal(inRoots(evil, [rootReal]), false);
    assert.equal(inRoots(rootReal, [rootReal]), true);
    assert.equal(inRoots(tmp(), [rootReal]), true);
    assert.equal(inRoots('relative', [rootReal]), false);
    assert.equal(inRoots(undefined, [rootReal]), false);
  } finally { fs.rmSync(evil, { recursive: true }); }
});

test('sessions roots', async () => {
  const { token } = await pairDevice();
  const d = fs.mkdtempSync(path.join(os.tmpdir(), '!roots-')); // sorts first; tmpdir may hold >200 dirs
  fs.mkdirSync(path.join(d, 'proj'));
  fs.mkdirSync(path.join(os.tmpdir(), '.echo-hidden-test'), { recursive: true });
  assert.equal((await fetch(`${tb}/sessions/roots`)).status, 401);
  const r = await fetch(`${tb}/sessions/roots`, { headers: bearer(token) });
  assert.equal(r.status, 200);
  const { roots } = await r.json();
  assert.equal(roots[0].root, rootReal);
  assert.ok(roots[0].dirs.includes(path.basename(d)));
  assert.ok(!roots[0].dirs.some((n) => n.startsWith('.')));
  fs.rmSync(d, { recursive: true });
});

test('ext hook', async () => {
  const ext = (body, seg = hub.config.hookSecret) => fetch(`http://127.0.0.1:${hub.hookPort}/hook/ext/${seg}`, { method: 'POST', body: JSON.stringify(body) });
  const id = crypto.randomUUID();
  assert.equal((await ext(hp(id, 'Stop', { cwd: tmp() }))).status, 200);
  await waitFor(() => hub.sessions.get(id));
  const x = (await (await fetch(`${base}/sessions`)).json()).sessions.find((s) => s.id === id);
  assert.equal(x.source, 'external');
  assert.equal((await ext(hp(id, 'Stop'), 'deadbeef')).status, 403);
  assert.equal((await ext(hp(id, 'Stop'), 'x'.repeat(32))).status, 403);
  const own = await create();
  await waitFor(() => st(own) === 'running');
  assert.equal((await ext(hp(own, 'Stop'))).status, 200);
  await sleep(1800);
  assert.equal(st(own), 'running');
  assert.equal(hub.sessions.list().filter((s) => s.id === own).length, 1);
});

test('log rotation', () => {
  const f = path.join(tmp(), 'hub.log');
  fs.writeFileSync(f, 'a'.repeat(200));
  const log = openLog(f, { maxBytes: 100 });
  log('hello', 'world');
  log.close();
  assert.equal(fs.readFileSync(f + '.1', 'utf8'), 'a'.repeat(200));
  assert.ok(fs.statSync(f).size < 100);
  assert.match(fs.readFileSync(f, 'utf8'), /^\d{4}-\d\d-\d\dT[\d:.]+Z hello world\n$/);
});

test('no secrets in log', async () => {
  const out = [];
  const [ol, oe] = [console.log, console.error];
  console.log = console.error = (...a) => out.push(a.join(' '));
  let code, token;
  try {
    code = await mintCode();
    const r = await jpost(`${tb}/pair`, { code, deviceName: 'logcheck' });
    token = (await r.json()).token;
    await fetch(`${tb}/sessions`, { headers: bearer(token) });
  } finally { console.log = ol; console.error = oe; }
  const text = out.join('\n');
  assert.ok(!text.includes(code) && !text.includes(token));
});

// ---- 02-04 installer tests (temp files only; never touch real ~/.claude or LaunchAgents) ----
import { spawnSync } from 'node:child_process';
const origSettings = () => ({
  permissions: { allow: ['Bash(ls)'] }, model: 'opus', statusLine: { type: 'command', command: 'x' },
  hooks: { PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'a' }] }], PostToolUse: [{ hooks: [{ type: 'command', command: 'b' }] }], SessionStart: [{ hooks: [{ type: 'command', command: 'c' }] }] },
});
const URL1 = 'http://127.0.0.1:8791/hook/ext/abc123';

test('hooks merge', async () => {
  const { merge, unmerge } = await import('./install/hooks-merge.js');
  const orig = origSettings();
  const m = merge(origSettings(), URL1);
  for (const ev of ['Stop', 'Notification']) {
    assert.equal(m.hooks[ev].length, 1);
    assert.deepEqual(m.hooks[ev][0].hooks, [{ type: 'http', url: URL1, timeout: 3 }]);
  }
  const { Stop, Notification, ...restHooks } = m.hooks;
  assert.deepEqual({ ...m, hooks: restHooks }, orig);
  assert.deepEqual(merge(structuredClone(m), URL1), m);
  const withUser = origSettings();
  withUser.hooks.Stop = [{ hooks: [{ type: 'command', command: 'mine' }] }];
  const m2 = merge(withUser, URL1);
  assert.equal(m2.hooks.Stop.length, 2);
  assert.equal(m2.hooks.Stop[0].hooks[0].command, 'mine');
  assert.deepEqual(unmerge(m), orig);
  const u2 = unmerge(m2);
  assert.deepEqual(u2.hooks.Stop, [{ hooks: [{ type: 'command', command: 'mine' }] }]);
  assert.ok(!('Notification' in u2.hooks));
});

test('hooks merge cli', async () => {
  const d = tmp(), data = path.join(d, 'data'), f = path.join(d, 'settings.json');
  const bytes = JSON.stringify(origSettings(), null, 2);
  fs.writeFileSync(f, bytes);
  const env = { ...process.env, ECHO_DATA_DIR: data, ECHO_HOOK_PORT: '8791', ECHO_CLAUDE_HOME: d };
  const script = path.join(import.meta.dirname, 'install', 'hooks-merge.js');
  const run = (...a) => spawnSync(process.execPath, [script, ...a], { env, encoding: 'utf8' });
  const r = run('merge', f);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(fs.readFileSync(f + '.echo-bak', 'utf8'), bytes);
  if (!posix.skip) assert.equal(fs.statSync(f).mode & 0o777, 0o600);
  const secret = JSON.parse(fs.readFileSync(path.join(data, 'config.json'), 'utf8')).hookSecret;
  assert.ok(fs.readFileSync(f, 'utf8').includes(`/hook/ext/${secret}`));
  assert.equal(run('merge', f).status, 0);
  assert.equal(fs.readFileSync(f + '.echo-bak', 'utf8'), bytes);
  assert.equal(run('unmerge', f).status, 0);
  assert.deepEqual(JSON.parse(fs.readFileSync(f, 'utf8')), origSettings());
  fs.writeFileSync(f, '{bad');
  assert.notEqual(run('merge', f).status, 0);
  assert.equal(fs.readFileSync(f, 'utf8'), '{bad');
});

test('plist dry run', { skip: process.platform !== 'darwin' }, () => {
  const plist = path.join(os.homedir(), 'Library', 'LaunchAgents', 'com.rishizamvar.echo-hub.plist');
  const before = fs.existsSync(plist);
  const sh = path.join(import.meta.dirname, 'install', 'install.sh');
  const r = spawnSync('sh', [sh, '--dry-run'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const lint = spawnSync('plutil', ['-lint', '-'], { input: r.stdout, encoding: 'utf8' });
  assert.equal(lint.status, 0, lint.stdout + lint.stderr);
  for (const s of ['com.rishizamvar.echo-hub', 'RunAtLoad', 'KeepAlive', 'ThrottleInterval', path.join(import.meta.dirname, 'server.js'), 'launchd.log']) assert.ok(r.stdout.includes(s), s);
  assert.equal(fs.existsSync(plist), before);
});

// ---- plan 04-01: push ----
import crypto from 'node:crypto';
import { makeJwt, apnsRequest, alertText } from './apns.js';

const ecPem = () => {
  const kp = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  return { publicKey: kp.publicKey, pem: kp.privateKey.export({ type: 'pkcs8', format: 'pem' }) };
};
const b64u = (s) => Buffer.from(s, 'base64url');
const TOK_A = 'ab'.repeat(32);
const TOK_B = 'bc'.repeat(32);

async function apnsHub({ seed, apnsCooldownMs } = {}) {
  const dir = tmp();
  const keyPath = path.join(dir, 'AuthKey_KID123.p8');
  fs.writeFileSync(keyPath, ecPem().pem, { mode: 0o600 });
  fs.writeFileSync(path.join(dir, 'config.json'), JSON.stringify({
    owner: 'owner@example.com', roots: [fs.realpathSync(os.tmpdir())],
    apns: { keyId: 'KID123', teamId: '373D7DZ9NM', bundleId: 'com.rishizamvar.echor2', keyPath },
  }));
  if (seed) fs.writeFileSync(path.join(dir, 'devices.json'), JSON.stringify(seed));
  const calls = [];
  const script = {}; // token -> array of results / Errors, consumed in order
  const apnsSend = async (req) => {
    calls.push(req);
    const tok = req.headers[':path'].split('/').pop();
    const next = script[tok]?.shift();
    if (next instanceof Error) throw next;
    return next ?? { status: 200 };
  };
  const h = await startHub({ port: 0, claudeCmd: [process.execPath, fake], dataDir: dir, killOnClose: true, hookPort: 0,
    tailscale: [process.execPath, fakeTs], tailnetPort: 0, allowLoopbackTailnet: true, whoisTtlMs: 0, apnsSend, apnsCooldownMs });
  const t = `http://127.0.0.1:${await h.tailnetReady}`;
  return { h, dir, calls, script, base: `http://127.0.0.1:${h.port}`, tb: t, devicesFile: path.join(dir, 'devices.json') };
}

test('apns jwt', () => {
  const { publicKey, pem } = ecPem();
  const jwt = makeJwt({ keyId: 'KID123', teamId: '373D7DZ9NM', key: pem }, 1700000000);
  const [h, c, s] = jwt.split('.');
  assert.deepEqual(JSON.parse(b64u(h)), { alg: 'ES256', kid: 'KID123' });
  assert.deepEqual(JSON.parse(b64u(c)), { iss: '373D7DZ9NM', iat: 1700000000 });
  assert.equal(b64u(s).length, 64);
  assert.equal(crypto.verify('sha256', Buffer.from(h + '.' + c), { key: publicKey, dsaEncoding: 'ieee-p1363' }, b64u(s)), true);
});

test('apns payload', () => {
  const S = crypto.randomUUID();
  const r = apnsRequest({ token: TOK_A, env: 'sandbox', bundleId: 'com.rishizamvar.echor2', sessionId: S, title: 'x'.repeat(100), body: 'y'.repeat(300) });
  assert.equal(r.host, 'https://api.sandbox.push.apple.com');
  assert.equal(apnsRequest({ token: TOK_A, env: 'production', bundleId: 'b' }).host, 'https://api.push.apple.com');
  assert.equal(r.headers[':path'], `/3/device/${TOK_A}`);
  assert.equal(r.headers['apns-topic'], 'com.rishizamvar.echor2');
  assert.equal(r.headers['apns-push-type'], 'alert');
  assert.equal(r.headers['apns-priority'], '10');
  assert.equal(r.headers['apns-collapse-id'], S);
  const { alert, sound } = r.payload.aps;
  assert.ok(alert.title.length <= 60 && alert.title.endsWith('…'));
  assert.ok(alert.body.length <= 140 && alert.body.endsWith('…'));
  assert.equal(sound, 'default');
  assert.equal(r.payload.aps['thread-id'], S);
  assert.equal(r.payload.sessionId, S);
  assert.deepEqual(alertText('done', { title: '', cwd: '/a/b/proj', lastStop: 'first line\nsecond' }), { title: 'proj', body: 'first line' });
  assert.equal(alertText('waiting', { title: 'T', lastMessage: 'Claude needs your permission' }).body, 'Claude needs your permission');
  assert.equal(alertText('exited', { title: 'T', exitCode: 3 }).body, 'exited (code 3)');
});

test('push token register', async () => {
  const { token, deviceId } = await pairDevice('pusher');
  const reg = (body, headers = bearer(token), b = tb) => jpost(`${b}/devices/push`, body, headers);
  assert.equal((await reg({ token: TOK_A, env: 'sandbox' })).status, 200);
  assert.equal((await reg({ token: 'zz', env: 'sandbox' })).status, 400);
  assert.equal((await (await reg({ token: 'zz', env: 'sandbox' })).json()).error, 'bad_push');
  assert.equal((await reg({ token: TOK_A, env: 'dev' })).status, 400);
  assert.equal((await reg({ token: TOK_A, env: 'sandbox' }, {})).status, 401);
  const lb = await reg({ token: TOK_A, env: 'sandbox' }, {}, base);
  assert.equal(lb.status, 400);
  assert.equal((await lb.json()).error, 'no_device');
  const file = path.join(hubDir, 'devices.json');
  const dev = () => JSON.parse(fs.readFileSync(file, 'utf8')).find((d) => d.id === deviceId);
  assert.equal(dev().push.token, TOK_A);
  assert.equal(dev().push.env, 'sandbox');
  assert.ok(!(await (await fetch(`${base}/admin/devices`)).text()).includes(TOK_A));
  assert.equal((await jpost(`${base}/admin/revoke`, { id: deviceId })).status, 200);
  assert.ok(!fs.readFileSync(file, 'utf8').includes(TOK_A));
});

test('push send + cleanup', async () => {
  const a = await apnsHub();
  try {
    assert.equal((await (await fetch(`${a.base}/health`)).json()).push, 'ready');
    const dA = await pairDevice('A', a.base, a.tb);
    const dB = await pairDevice('B', a.base, a.tb);
    assert.equal((await jpost(`${a.tb}/devices/push`, { token: TOK_A, env: 'sandbox' }, bearer(dA.token))).status, 200);
    assert.equal((await jpost(`${a.tb}/devices/push`, { token: TOK_B, env: 'production' }, bearer(dB.token))).status, 200);
    a.script[TOK_A] = [{ status: 410, reason: 'Unregistered' }];
    const r = await jpost(`${a.base}/admin/test-push`, {});
    assert.equal(r.status, 200);
    assert.equal((await r.json()).sent, 2);
    const hostOf = (tok) => a.calls.find((c) => c.headers[':path'].endsWith(tok)).host;
    assert.equal(hostOf(TOK_A), 'https://api.sandbox.push.apple.com');
    assert.equal(hostOf(TOK_B), 'https://api.push.apple.com');
    const file = fs.readFileSync(a.devicesFile, 'utf8');
    assert.ok(!file.includes(TOK_A));
    assert.ok(file.includes(TOK_B));

    const callsFor = () => a.calls.filter((c) => c.headers[':path'].endsWith(TOK_B)).length;
    for (const [seq, want] of [
      [[{ status: 500 }, { status: 200 }], 2],
      [[{ status: 500 }, { status: 500 }, { status: 200 }], 2],
      [[new Error('conn'), { status: 200 }], 2],
    ]) {
      a.calls.length = 0;
      a.script[TOK_B] = seq;
      await jpost(`${a.base}/admin/test-push`, {});
      assert.equal(callsFor(), want);
    }
    // device-scoped test route: caller's token only
    a.calls.length = 0;
    const own = await jpost(`${a.tb}/devices/push/test`, {}, bearer(dB.token));
    assert.equal(own.status, 200);
    assert.equal((await own.json()).sent, 1);
    assert.equal((await jpost(`${a.tb}/devices/push/test`, {}, bearer(dA.token))).status, 404); // A's token was dropped
  } finally { a.h.close(); }
});

test('hub started push', async () => {
  const seed = [{ id: crypto.randomUUID(), name: 'seeded', hash: 'a'.repeat(64), createdAt: new Date().toISOString(), lastSeen: null, push: { token: TOK_A, env: 'sandbox', at: new Date().toISOString() } }];
  const a = await apnsHub({ seed });
  try {
    await waitFor(() => a.calls.length >= 1);
    await sleep(300);
    assert.equal(a.calls.length, 1);
    assert.equal(a.calls[0].payload.aps.alert.title, 'echo hub');
    assert.ok(a.calls[0].payload.aps.alert.body.startsWith('online · '));
  } finally { a.h.close(); }
});

test('push unconfigured', async () => {
  assert.equal((await (await fetch(`${base}/health`)).json()).push, 'unconfigured');
  const r = await jpost(`${base}/admin/test-push`, {});
  assert.equal(r.status, 503);
  assert.equal((await r.json()).error, 'push_unconfigured');
});

// plan 04-02: alerts
import { Push } from './apns.js';
const seedDev = () => [{ id: crypto.randomUUID(), name: 's', hash: 'a'.repeat(64), createdAt: new Date().toISOString(), lastSeen: null, push: { token: TOK_A, env: 'sandbox', at: new Date().toISOString() } }];
const forSession = (a, id) => a.calls.filter((c) => c.payload.sessionId === id);
const hookTo = (a, body) => fetch(`http://127.0.0.1:${a.h.hookPort}/hook`, { method: 'POST', headers: { 'x-echo-secret': a.h.secret }, body: JSON.stringify(body) });
const mkSession = async (a) => (await (await fetch(`${a.base}/sessions`, { method: 'POST', body: JSON.stringify({ cwd: tmp() }) })).json()).id;

test('alert on stop/notification/exit', async () => {
  const a = await apnsHub({ seed: seedDev(), apnsCooldownMs: 200 });
  try {
    const id = await mkSession(a);
    await hookTo(a, { session_id: id, hook_event_name: 'Stop', last_assistant_message: 'All tests pass\nmore' });
    await waitFor(() => forSession(a, id).length >= 1, 3000);
    await sleep(300);
    assert.equal(forSession(a, id).length, 1);
    assert.equal(forSession(a, id)[0].headers['apns-collapse-id'], id);
    assert.equal(forSession(a, id)[0].payload.aps.alert.body, 'All tests pass');
    await hookTo(a, { session_id: id, hook_event_name: 'Notification', message: 'Claude needs your permission to use Bash' });
    await waitFor(() => forSession(a, id).length >= 2, 3000);
    assert.equal(forSession(a, id)[1].payload.aps.alert.body, 'Claude needs your permission to use Bash');
  } finally { a.h.close(); }
});

test('no exited push on user stop', async () => {
  const a = await apnsHub({ seed: seedDev() });
  try {
    const id = await mkSession(a);
    assert.equal((await fetch(`${a.base}/sessions/${id}/stop`, { method: 'POST' })).status, 200);
    await sleep(500);
    assert.equal(forSession(a, id).filter((c) => c.payload.aps.alert.body.startsWith('exited')).length, 0);
  } finally { a.h.close(); }
});

test('exited push on crash', { skip: process.platform === 'win32' }, async () => {
  const a = await apnsHub({ seed: seedDev() });
  try {
    const id = await mkSession(a);
    process.kill(a.h.sessions.get(id).pid, 'SIGKILL');
    await waitFor(() => forSession(a, id).length >= 1, 3000);
    assert.ok(forSession(a, id)[0].payload.aps.alert.body.startsWith('exited (code'));
  } finally { a.h.close(); }
});

test('external alert', async () => {
  const a = await apnsHub({ seed: seedDev() });
  try {
    const id = crypto.randomUUID();
    await fetch(`http://127.0.0.1:${a.h.hookPort}/hook/ext/${a.h.config.hookSecret}`, { method: 'POST',
      body: JSON.stringify({ session_id: id, hook_event_name: 'Notification', message: 'waiting on you', cwd: '/x/proj' }) });
    await waitFor(() => forSession(a, id).length >= 1, 3000);
    await sleep(200);
    assert.equal(forSession(a, id).length, 1);
    assert.equal(forSession(a, id)[0].payload.aps.alert.title, 'proj');
    assert.equal(forSession(a, id)[0].payload.aps.alert.body, 'waiting on you');
  } finally { a.h.close(); }
});

test('cooldown collapse', async () => {
  let clock = 0;
  const timers = [];
  const calls = [];
  const devices = { pushTargets: () => [{ token: TOK_A, env: 'sandbox' }], dropPush() {} };
  const p = new Push({ apns: { keyId: 'K', teamId: 'T', bundleId: 'b', keyPath: (() => { const f = path.join(tmp(), 'k.p8'); fs.writeFileSync(f, ecPem().pem, { mode: 0o600 }); return f; })() },
    devices, send: async (r) => { calls.push(r); return { status: 200 }; }, now: () => clock, cooldownMs: 10000,
    setTimer: (fn) => { const t = { fn }; timers.push(t); return t; } });
  const s = { id: 'sid', title: 'T', lastStop: 'fin', lastMessage: 'need' };
  await p.alert(s, 'done'); await p.alert(s, 'done'); await p.alert(s, 'done');
  assert.equal(calls.length, 1);
  await p.alert(s, 'waiting');
  assert.equal(calls.length, 1);
  clock = 10000;
  await timers[0].fn();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].payload.aps.alert.body, 'need');
  clock = 25000;
  await p.alert(s, 'waiting');
  assert.equal(calls.length, 3);
  p.close();
});
