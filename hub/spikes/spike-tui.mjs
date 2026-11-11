// Phase 1 PC spike probe. Run from hub/: node spikes/spike-tui.mjs <trusted-cwd>
// Diagnostics only. Loopback only. Never skips permissions.
import pty from 'node-pty';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import readline from 'node:readline';
import { scrubEnv, resolveClaude } from '../sessions.js';

const cwd = process.argv[2];
if (!cwd) { console.error('usage: node spikes/spike-tui.mjs <trusted-cwd>'); process.exit(2); }
const secret = crypto.randomBytes(8).toString('hex');
const uuid = crypto.randomUUID();
const PORT = 8791;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const show = (label, v) => console.log(`${label} ${JSON.stringify(v)}`);
const slice = (s) => (s.length > 600 ? s.slice(0, 600) : s);

// hook listener (127.0.0.1 only)
let stopCount = 0;
const hooks = [];
const srv = http.createServer((req, res) => {
  let body = '';
  req.on('data', (d) => (body += d));
  req.on('end', () => {
    const ok = req.headers['x-echo-secret'] === secret;
    console.log(`HOOK ${req.method} ${req.url} secret=${ok} ${body.slice(0, 1500)}`);
    hooks.push(req.url);
    if (req.url.endsWith('/Stop')) stopCount++;
    res.writeHead(200); res.end();
  });
});
await new Promise((r) => srv.listen(PORT, '127.0.0.1', r));

// hooks.json
const hook = (ev) => [{ hooks: [{ type: 'http', url: `http://127.0.0.1:${PORT}/hook/${ev}`,
  headers: { 'X-Echo-Secret': '$ECHO_SECRET' }, allowedEnvVars: ['ECHO_SECRET'], timeout: 5 }] }];
const settings = path.join(os.tmpdir(), `echo-spike-${uuid}.json`);
fs.writeFileSync(settings, JSON.stringify({ hooks: { Stop: hook('Stop'), Notification: hook('Notification'), SubagentStop: hook('SubagentStop') } }));

const transcriptExists = () => {
  const root = path.join(os.homedir(), '.claude', 'projects');
  try { return fs.readdirSync(root).map((d) => path.join(root, d, `${uuid}.jsonl`)).filter((f) => fs.existsSync(f)); }
  catch { return []; }
};

const [cmd, ...pre] = resolveClaude();
const cols = 120, rows = 30;
const p = pty.spawn(cmd, [...pre, '--session-id', uuid, '--settings', settings], {
  name: 'xterm-256color', cols, rows, cwd, useConpty: true,
  env: { ...scrubEnv(process.env), ECHO_SECRET: secret },
});
let buf = '';
let exited = null;
p.onData((d) => { buf += d; });
p.onExit((e) => { exited = e; console.log(`ONEXIT ${JSON.stringify(e)}`); });
const take = () => { const s = buf; buf = ''; return s; };
const waitStop = async (n, ms = 60000) => { const t = Date.now(); while (stopCount < n && Date.now() - t < ms) await sleep(200); return stopCount >= n; };

console.log(`CMD ${cmd} ${pre.join(' ')}  UUID ${uuid}  CWD ${cwd}`);

console.log('== S2.1 first 1.5s output');
await sleep(1500);
show('raw', slice(take()));
show('transcript_before_prompt', transcriptExists());

console.log('== S2.2 bracketed paste "say pong" + CR');
p.write('\x1b[200~say pong\x1b[201~'); await sleep(500); p.write('\r');
show('stop_hook_fired', await waitStop(1));
show('raw_tail', take().slice(-600));
show('transcript_after_prompt', transcriptExists());

console.log('== S2.3 paste with embedded newline');
p.write('\x1b[200~say\nhello\x1b[201~'); await sleep(500); p.write('\r');
show('stop_hook_fired', await waitStop(2));
show('raw_tail', take().slice(-600));

console.log('== S2.4 arrows + UTF-8 (not submitted)');
p.write('\x1b[A'); await sleep(200); p.write('\x1b[B'); await sleep(200);
p.write('naïve café 日本語'); await sleep(600);
show('raw', slice(take()));
p.write('\x15'); await sleep(300); take();

console.log('== S2.5 resize 100x40 -> 120x30');
take(); p.resize(100, 40); await sleep(250); p.resize(cols, rows); await sleep(250);
{ const s = take(); show('bytes', s.length); show('raw', slice(s)); }

console.log('== S2.6 Ctrl-C during long answer');
p.write('\x1b[200~count slowly from 1 to 200, one number per line\x1b[201~'); await sleep(500); p.write('\r');
await sleep(4000); take();
p.write('\x03'); await sleep(1500);
const after1 = take(); await sleep(1500); const after2 = take();
show('interrupted_seen', /interrupt/i.test(after1));
show('output_stopped', after2.length < 50);
show('raw', slice(after1));
show('late_bytes', after2.length);

console.log('== S2.7 resize nudge repaint');
take(); p.resize(cols, rows + 1); p.resize(cols, rows); await sleep(500);
{ const s = take(); show('bytes', s.length); show('raw', slice(s)); }

console.log('== S5 hooks seen so far');
show('urls', hooks);

console.log('== S4 process tree');
console.log(`PTY_PID ${p.pid}`);
console.log('Inspect/kill from another shell now, then press Enter here.');
await new Promise((r) => readline.createInterface({ input: process.stdin }).once('line', r));
await sleep(500);
show('onExit', exited);
console.log('transcript_final', JSON.stringify(transcriptExists()));
try { p.kill(); } catch {}
srv.close(); fs.rmSync(settings, { force: true });
process.exit(0);
