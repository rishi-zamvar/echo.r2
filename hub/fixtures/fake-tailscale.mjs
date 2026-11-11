// Test double for the tailscale CLI. State file (env FAKE_TS_STATE): {ip, whois, exit}
import fs from 'node:fs';

const st = JSON.parse(fs.readFileSync(process.env.FAKE_TS_STATE, 'utf8'));
const a = process.argv.slice(2);
if (a[0] === 'ip' && a[1] === '-4') {
  if (!st.ip) process.exit(1);
  console.log(st.ip);
} else if (a[0] === 'whois' && a[1] === '--json') {
  if (st.exit) { console.error('peer not found'); process.exit(st.exit); }
  process.stdout.write(typeof st.whois === 'string' ? st.whois : JSON.stringify(st.whois));
} else process.exit(2);
