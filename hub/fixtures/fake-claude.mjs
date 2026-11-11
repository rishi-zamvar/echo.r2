// Test double for `claude`. Plans 02-03 rely on these exact output strings.
import { spawn } from 'node:child_process';
const a = process.argv.slice(2);
if (a.includes('--version')) { console.log('fake-claude 0.0.0'); process.exit(0); }
if (process.stdin.isTTY) process.stdin.setRawMode(true);
const sid = a[a.indexOf('--session-id') + 1];
process.stdout.write(`READY session=${sid}\r\n`);
let n = 0;
setInterval(() => process.stdout.write(`tick ${++n}\r\n`), 100);
process.stdin.on('data', (c) => {
  const s = c.toString();
  process.stdout.write('IN:' + JSON.stringify(s) + '\r\n');
  if (s.includes('\x03')) process.stdout.write('^C-RECEIVED\r\n');
});
if (process.env.FAKE_GRANDCHILD === '1') {
  const g = spawn('sleep', ['300'], { stdio: 'ignore' });
  process.stdout.write(`GRANDCHILD ${g.pid}\r\n`);
}
