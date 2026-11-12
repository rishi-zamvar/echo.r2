// P0-1 reproduction: restart an isolated hub N times while a fake Even Terminal churns `claude --resume`
// children, and prove the hub never signals them. Usage: node hub/tools/safety-harness.mjs [N=50]
// ponytail: isolated only (temp dirs, fake claude, own processes); the live check with a real Even Terminal session is Rishi's step in 05-12.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { startHub } from '../server.js';

const N = +process.argv[2] || 50;
const fake = path.join(import.meta.dirname, '..', 'fixtures', 'fake-claude.mjs');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'echo-safety-'));
const dataDir = path.join(root, 'data'), claudeHome = path.join(root, 'claude'), work = path.join(root, 'work');
for (const d of [dataDir, claudeHome, work, path.join(root, 'bin')]) fs.mkdirSync(d, { recursive: true });
fs.writeFileSync(path.join(dataDir, 'config.json'), JSON.stringify({ roots: [fs.realpathSync(root)] }));
const ET_ID = crypto.randomUUID();
// D-03: ET_ID's transcript says entrypoint sdk-ts, so takeover/resume must be refused with 409 even_terminal
fs.mkdirSync(path.join(claudeHome, 'projects', '-et'), { recursive: true });
fs.writeFileSync(path.join(claudeHome, 'projects', '-et', `${ET_ID}.jsonl`), JSON.stringify({ type: 'user', entrypoint: 'sdk-ts', cwd: work, message: { content: 'hi' } }) + '\n');
const log = path.join(root, 'et.log');
const etScript = path.join(root, 'bin', 'even-terminal'); // command line contains bin/even-terminal, like the real one

// Fake Even Terminal: every 300 ms a detached (own group, like node-pty) child lives ~1 s, then gets SIGHUP from us.
fs.writeFileSync(etScript, `const { spawn } = require('node:child_process'); const fs = require('node:fs');
const w = (s) => fs.appendFileSync(${JSON.stringify(log)}, s + '\\n');
w('parent ' + process.pid);
setInterval(() => {
  const c = spawn(process.execPath, [${JSON.stringify(fake)}, '--resume', ${JSON.stringify(ET_ID)}], { detached: true, stdio: 'ignore' });
  w('child ' + c.pid);
  c.on('exit', (code, sig) => w('exit ' + c.pid + ' ' + sig));
  setTimeout(() => { try { c.kill('SIGHUP'); } catch {} }, 1000);
}, 300);`);
const et = spawn(process.execPath, [etScript], { detached: true, stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const lines = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean).map((l) => l.split(' ')) : []);
const liveChildren = () => {
  const gone = new Set(lines().filter((l) => l[0] === 'exit').map((l) => l[1]));
  return lines().filter((l) => l[0] === 'child' && !gone.has(l[1])).map((l) => +l[1]);
};
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

let bad = 0;
try {
  await sleep(500);
  for (let i = 1; i <= N; i++) {
    const kids = liveChildren();
    fs.writeFileSync(path.join(dataDir, 'sessions.json'), JSON.stringify([
      ...kids.flatMap((pid) => [{ id: ET_ID, pid, state: 'running', source: 'hub' }, { id: crypto.randomUUID(), pid, state: 'running', source: 'hub' }]),
      { id: ET_ID, pid: et.pid, state: 'running', source: 'hub' },
    ]));
    const h = await startHub({ port: 0, hookPort: 0, dataDir, claudeHome, claudeCmd: [process.execPath, fake], killOnClose: true });
    try {
      const b = `http://127.0.0.1:${h.port}`;
      await fetch(`${b}/sessions`);
      const r = await fetch(`${b}/sessions`, { method: 'POST', body: JSON.stringify({ cwd: work }) });
      const { id } = await r.json();
      await fetch(`${b}/sessions/${id}/stop`, { method: 'POST' });
      for (const a of ['takeover', 'resume']) {
        const x = await fetch(`${b}/sessions/${ET_ID}/${a}`, { method: 'POST' });
        if (x.status !== 409 || (await x.json()).error !== 'even_terminal') { console.log(`safety FAIL ${a} ${x.status}`); process.exit(1); }
      }
    } finally { h.close(); }
    await sleep(50);
    const killed = lines().filter((l) => l[0] === 'exit' && (l[2] === 'SIGKILL' || l[2] === 'SIGTERM'));
    if (killed.length || !alive(et.pid)) { bad = killed.length || 1; break; }
  }
} finally {
  try { process.kill(et.pid, 'SIGKILL'); } catch {} // only the parent we spawned
  for (const pid of liveChildren()) try { process.kill(-pid, 'SIGKILL'); } catch {}
  fs.rmSync(root, { recursive: true, force: true });
}
if (bad) { console.log(`safety FAIL ${bad} external kills`); process.exit(1); }
console.log(`safety ok ${N} restarts, 0 external kills`);
process.exit(0);
