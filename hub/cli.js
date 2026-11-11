import path from 'node:path';
import WebSocket from 'ws';

const port = process.env.ECHO_PORT || 8790;
const base = `127.0.0.1:${port}`;
const [cmd, ...args] = process.argv.slice(2);

async function api(method, p, body) {
  const r = await fetch(`http://${base}${p}`, { method, body: body && JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) { console.error(JSON.stringify(j)); process.exit(1); }
  return j;
}

function usage() {
  console.error('usage: cli.js list | new <cwd> [prompt...] | attach <id> [--since n] [--for s]');
  process.exit(2);
}

async function resolveId(prefix) {
  const { sessions } = await api('GET', '/sessions');
  const m = sessions.filter((s) => s.id.startsWith(prefix));
  if (m.length !== 1) { console.error(m.length ? 'ambiguous id' : 'no such session'); process.exit(1); }
  return m[0].id;
}

if (cmd === 'list') {
  const { sessions } = await api('GET', '/sessions');
  for (const s of sessions) console.log([s.id.slice(0, 8), s.state, s.source, s.cwd, s.label ?? s.title].filter(Boolean).join(' '));
} else if (cmd === 'new') {
  if (!args[0]) usage();
  const prompt = args.slice(1).join(' ') || undefined;
  console.log((await api('POST', '/sessions', { cwd: path.resolve(args[0]), prompt })).id);
} else if (cmd === 'attach') {
  if (!args[0]) usage();
  const opt = (name) => { const i = args.indexOf(name); return i > 0 ? args[i + 1] : undefined; };
  const since = opt('--since');
  const forSec = opt('--for');
  const id = await resolveId(args[0]);
  const q = new URLSearchParams();
  if (since !== undefined) q.set('since', since);
  // epoch only matters for a resume; ask the hub for the current one so a same-boot resume is not reset
  // ponytail: a hub restart between detach and re-attach is not detected here; pass epoch from the detach line when that matters
  if (since !== undefined) q.set('epoch', (await api('GET', '/sessions')).epoch);
  const ws = new WebSocket(`ws://${base}/sessions/${id}/stream?${q}`);
  let seq = 0, epoch = '', done = false;
  const tty = process.stdin.isTTY;
  const sendSize = () => ws.send(JSON.stringify({ type: 'resize', cols: process.stdout.columns, rows: process.stdout.rows }));
  const detach = () => {
    if (done) return;
    done = true;
    if (tty) process.stdin.setRawMode(false);
    console.error(`detached seq=${seq} epoch=${epoch}`);
    ws.terminate();
    process.exit(0);
  };
  ws.on('open', () => {
    if (!tty) return;
    sendSize();
    process.stdout.on('resize', sendSize);
    process.stdin.setRawMode(true);
    process.stdin.on('data', (d) => {
      if (d.includes(0x1d)) return detach(); // Ctrl-]
      ws.send(JSON.stringify({ type: 'keys', data: d.toString('utf8') }));
    });
  });
  ws.on('message', (m) => {
    const f = JSON.parse(m.toString());
    if (f.kind === 'state' && !process.stdout.isTTY) console.error(`[state] ${f.state}`);
    if (f.type === 'hello') epoch = f.epoch;
    else if (f.type === 'reset') process.stdout.write('\x1bc');
    else if (f.type === 'error') console.error(f.code);
    if (f.kind === 'term') process.stdout.write(Buffer.from(f.data, 'base64'));
    if (f.seq) seq = f.seq;
  });
  ws.on('close', detach);
  ws.on('error', (e) => { console.error(e.message); process.exit(1); });
  if (forSec) setTimeout(detach, +forSec * 1000);
} else usage();
