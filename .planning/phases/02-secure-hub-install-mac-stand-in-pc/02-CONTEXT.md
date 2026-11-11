# Phase 2: Secure Hub & Install (Mac stand-in + PC) - Context

**Gathered:** 2026-11-11
**Status:** Ready for planning
**Mode:** --auto (recommended defaults; see 02-DISCUSSION-LOG.md)

<domain>
## Phase Boundary

Make the Phase 1 hub safe to expose to the paired phone over Tailscale and keep it running unattended. PC is down ~1 month, so the **Mac (`rishis-macbook-pro`, 100.125.215.102) is the live stand-in hub** now (launchd); the Windows install path (Task Scheduler + firewall) is written in this phase but verified only when the PC returns (park as a PC checkpoint like 01-05/01-06).

Requirements: HUB-01, HUB-02, HUB-03, HUB-04, AUTH-01, AUTH-03. Hub-side of AUTH-02 (header bearer auth) lands here; Keychain storage is Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Listeners & binding
- **D-01:** Two app-facing listeners on port 8790: (a) **tailnet listener** bound to the Tailscale IPv4 from `tailscale ip -4` — requires whois + bearer token; (b) **loopback listener** 127.0.0.1:8790 — no auth, for the local CLI and admin routes (pair code, devices, revoke). Hook listener stays 127.0.0.1:8791. Never bind 0.0.0.0 (keep the grep gate).
- **D-02:** Retry-bind with backoff (1 s → 30 s cap, forever) when Tailscale has no IP yet at login; loopback listener starts immediately. Log one terse line per state change.
- **D-03:** Tailscale CLI path resolved per OS: macOS `/usr/local/bin/tailscale` else `/Applications/Tailscale.app/Contents/MacOS/Tailscale`; Windows `C:\Program Files\Tailscale\tailscale.exe`. Overridable via `ECHO_TAILSCALE`.

### Identity (whois)
- **D-04:** On every tailnet request/WS upgrade: `execFile(tailscale, ['whois','--json', remoteIP])`, cache per IP 60 s. Allow only if `UserProfile.LoginName` equals configured `owner` (default from first successful pair, stored in `~/.echo-hub/config.json`; current tailnet login is `rishizamvar@`). Non-zero exit, parse error, or mismatch → 403. Fail closed.
- **D-05:** Tagged-node edge case (no user profile) → reject; documented in RUNBOOK.

### Tokens & pairing
- **D-06:** `node hub/cli.js pair [device-name]` → loopback `POST /admin/pair-code` → hub returns an 8-char code (Crockford base32, no ambiguous chars), single-use, expires 5 min; only one live code at a time. CLI prints the code (glasses-friendly: code only + expiry).
- **D-07:** Phone calls tailnet `POST /pair {code, deviceName}` (whois required, no token yet) → `201 {token, deviceId}`. Token = 32 random bytes base64url; store only SHA-256 + deviceId + name + createdAt + lastSeen in `~/.echo-hub/devices.json` (atomic write, mode 600). 5 wrong codes → current code invalidated.
- **D-08:** All other tailnet routes + WS require `Authorization: Bearer <token>` (header only, never query string); compare hashes with `crypto.timingSafeEqual`. Missing/invalid → 401 JSON `{error:'unauthorized'}`; WS upgrade rejected with 401 before handshake.
- **D-09:** `cli devices` lists paired devices; `cli revoke <deviceId|name>` deletes it → next request 401. Revocation takes effect immediately (open WS sockets for that device are closed).

### Session safety
- **D-10:** `POST /sessions` cwd must resolve (realpath) inside an allowlisted root from `config.json.roots` (default `[~/Documents/Projects, ~]` on Mac; PC default `%USERPROFILE%\Projects`). Outside → 400 `bad_cwd`. Never pass `--dangerously-skip-permissions`.
- **D-11:** `GET /sessions/roots` (authed) returns the allowlist + immediate subdirectories so the app can offer a picker in Phase 3.

### Health
- **D-12:** `GET /health` on tailnet requires whois only (no token) so an unpaired app can find the hub; returns `{ok, protocol, version, gitSha, uptime, os, hubName}`. gitSha read once at startup via `git rev-parse --short HEAD` (fallback `unknown`). Loopback `/health` identical.

### Autostart & install — Mac (live)
- **D-13:** `hub/install/install.sh` writes `~/Library/LaunchAgents/com.rishizamvar.echo-hub.plist`: absolute node path (`command -v node`), `RunAtLoad`, `KeepAlive` (restart on crash), `ThrottleInterval 10`, `WorkingDirectory` = repo `hub/`, `EnvironmentVariables.PATH` including the dir of `claude` and tailscale, stdout/stderr → `~/.echo-hub/hub.log`. Then `launchctl bootstrap gui/$UID` (or `bootout` + bootstrap if loaded). Idempotent. `uninstall.sh` reverses it.
- **D-14:** Mac sleep: hub is unreachable while the Mac sleeps — accepted for the stand-in; RUNBOOK notes it. No caffeinate/pmset changes.

### Autostart & install — Windows (written, verify later)
- **D-15:** `hub/install/install.ps1`: Register-ScheduledTask "echo-hub" At log on (current user, interactive, no stored password), action = absolute `node.exe hub\server.js` hidden window, restart on failure every 1 min ×999, no execution time limit, no battery conditions, MultipleInstances IgnoreNew; firewall rule allowing inbound TCP 8790 from 100.64.0.0/10 only. `uninstall.ps1` reverses. Marked UNVERIFIED; PC checkpoint plan records results later.

### Global hooks for external sessions
- **D-16:** Installer merges http `Stop` + `Notification` hooks into `~/.claude/settings.json` so external sessions report state: backup to `settings.json.echo-bak` first, tag entries with a marker (url contains `/hook/ext/<secret>`), never overwrite other hooks, idempotent; uninstall removes only marked entries. Secret for global hooks is a persistent random path segment stored in `config.json` (settings.json is user-only readable). Hook timeout 3 s; hub down = hook fails fast, Claude unaffected. Hub-owned sessions keep per-process `--settings` hooks (Phase 1); hub ignores duplicate global-hook events for hub-owned session ids.

### Deploy
- **D-17:** `hub/install/deploy.sh` (Mac) / `deploy.ps1` (PC): `git pull --ff-only` → `npm ci --omit=dev` in hub/ → restart (`launchctl kickstart -k gui/$UID/com.rishizamvar.echo-hub` / `schtasks /End` + `/Run`) → poll loopback `/health` until `gitSha` == new HEAD (30 s timeout) → print `deployed <sha>` or `deploy FAILED`.

### Logs & runbook
- **D-18:** Log rotation in-process: when `hub.log` > 5 MB at startup or hourly, rename to `hub.log.1` (one generation). Never log tokens, codes after use, Authorization headers, or transcript content.
- **D-19:** `hub/RUNBOOK.md`: install, pair, revoke, deploy, logs, Mac-sleep caveat, Tailscale key-expiry (disable for hub node), recommended Tailscale ACL (phone → hub:8790 only), PC-return checklist (resume 01-05/01-06 + Phase 2 PC checkpoint).

### File budget
- **D-20:** New code goes in a new `hub/auth.js` (whois, tokens, pairing, devices) + edits to server.js/cli.js; scripts under `hub/install/`. Tests stay in `hub/hub.test.js` (whois stubbed via `ECHO_TAILSCALE` pointing to a fake script).

### Claude's Discretion
- Exact backoff numbers, code alphabet, JSON field names beyond those listed, plist label details.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md` (HUB-01..04, AUTH-01, AUTH-03), `.planning/ROADMAP.md` §Phase 2, `.planning/STATE.md`
- `.planning/phases/01-hub-session-engine/SKELETON.md` — wire protocol v1, file layout
- `.planning/phases/01-hub-session-engine/01-CONTEXT.md` — D-14/D-15 hooks, D-22 loopback rule being relaxed here
- `.planning/phases/01-hub-session-engine/01-0{1..4}-SUMMARY.md` — what exists
- `.planning/research/PITFALLS.md` — auth/RCE, Task Scheduler, firewall, Tailscale key expiry
- `.planning/research/STACK.md` — whois, Task Scheduler, launchd rationale
- https://code.claude.com/docs/en/hooks — http hook config

</canonical_refs>

<code_context>
## Existing Code Insights

- `hub/server.js` `startHub({port, host, dataDir, hookPort, claudeHome})` — currently throws on any host but 127.0.0.1 (T-01-01); Phase 2 replaces this with the two-listener model.
- `hub/hooks.js` — `startHookServer`, per-boot secret, `hub-hooks.json` generator (matcher-group schema).
- `hub/store.js` — atomic JSON write helper; reuse for devices.json/config.json.
- `hub/cli.js` — list/new/attach/send/interrupt/stop over loopback; add pair/devices/revoke.
- Tailscale on Mac at `/usr/local/bin/tailscale`; Mac tailnet IP 100.125.215.102; phone `iphone-14-pro-max` 100.120.95.17, login `rishizamvar@`.

</code_context>

<specifics>
## Specific Ideas

- Glasses-friendly CLI output: `pair` prints just the code and expiry.
- PC (`zee-cloud`) currently absent from the tailnet peer list.

</specifics>

<deferred>
## Deferred Ideas

- Keychain token storage, pairing UI → Phase 3
- APNs, "hub started" push → Phase 4
- Auto-logon / wake-on-LAN for the PC → Rishi's call, later
- Mac sleep prevention → not doing for stand-in

</deferred>
