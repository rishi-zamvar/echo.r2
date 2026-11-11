# Phase 2: Secure Hub & Install (Mac stand-in + PC) - Research

**Researched:** 2026-11-11
**Domain:** Node `http`/`ws` hardening (whois + bearer auth), launchd/Task Scheduler autostart, Claude Code http hooks
**Confidence:** HIGH on whois/launchd/hooks (verified on this Mac / official docs); MEDIUM on Windows scripts (docs/knowledge only, PC down) and iOS WS header

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
D-01..D-20 as written in `02-CONTEXT.md` (two listeners 8790 tailnet+loopback, hook listener 8791 loopback; whois cache 60 s fail closed; 8-char Crockford pair code, 5 min single-use, 5 wrong = invalidate; token 32B base64url, SHA-256 stored, `timingSafeEqual`; Bearer header only; cwd allowlist via realpath; `/health` whois-only; launchd plist per D-13; Windows script per D-15 UNVERIFIED; global hooks merge per D-16 with `/hook/ext/<secret>`; deploy scripts D-17; in-process log rotation 5 MB / one generation D-18; RUNBOOK D-19; new `hub/auth.js` + edits, tests in `hub/hub.test.js` D-20).

### Claude's Discretion
Exact backoff numbers, code alphabet, JSON field names beyond those listed, plist label details.

### Deferred Ideas (OUT OF SCOPE)
Keychain storage / pairing UI (Phase 3), APNs / "hub started" push (Phase 4), PC auto-logon / WoL, Mac sleep prevention.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HUB-01 | Autostart at login + restart on crash | launchd `RunAtLoad`+`KeepAlive`+`ThrottleInterval` (Mac, live); Task Scheduler settings (PC, unverified) |
| HUB-02 | Tailnet-only, whois fails closed | Verified whois JSON shape; tailnet listener bind via `tailscale ip -4`; error behavior |
| HUB-03 | `/health` version/sha/protocol/uptime | D-12; gitSha once at startup |
| HUB-04 | One install script + one deploy script | `install.sh/.ps1`, `deploy.sh/.ps1`, settings.json merge |
| AUTH-01 | Pair via single-use 5-min code | `auth.js` pairing design, Crockford alphabet, attempt limiter |
| AUTH-03 | Revoke device from PC | `cli revoke`, ws close by deviceId |
</phase_requirements>

## Summary

Phase 1 code is small and shaped well for this: `startHub` builds one `http.Server` + `WebSocketServer({noServer})`; Phase 2 turns the single handler into a `makeHandler(ctx)` used by two `http.Server` instances (loopback: `ctx.tailnet=false`, tailnet: `ctx.tailnet=true`), both sharing one `wss` and one `upgrade` function. All auth logic goes in `hub/auth.js` (whois, devices, pairing, config). No new dependencies are needed (stdlib + existing `ws`/`node-pty`).

Live checks on this Mac show whois returns exactly the fields CONTEXT assumed; the owner login is `rishizamvar@icloud.com` (NOT the short `rishizamvar@` that `tailscale status` prints). Two findings need planner action: (1) the Mac node's key expires **2026-11-20** (9 days away; phone 2026-11-24) so disabling key expiry for the hub node is a Day-1 task, not just a RUNBOOK note; (2) D-18 in-process log rotation conflicts with launchd `StandardOutPath` (launchd keeps the fd open on the renamed file), so the hub must write its own log file.

**Primary recommendation:** Build `auth.js` first with the fake-tailscale test seam (`ECHO_TAILSCALE` serving both `ip -4` and `whois --json`), make server.js two-listener, then the Mac installer; PC scripts are written but parked.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Peer identity (whois) | Hub (Node) via Tailscale CLI | OS/Tailscale daemon | Daemon knows the WireGuard peer; hub only asks |
| Token verify / pairing / revoke | Hub (`auth.js`) | CLI over loopback | Hub is source of truth; CLI is admin client |
| Network exposure | Hub bind address + OS firewall (PC) | Tailscale ACL (RUNBOOK) | Defense in depth: bind, whois, token, firewall |
| Autostart / restart | OS (launchd / Task Scheduler) | Hub retry-bind loop | OS restarts process; hub handles Tailscale-not-up-yet |
| cwd allowlist | Hub (`sessions` start route) | — | Server-side enforcement; app only shows picker |
| External-session hooks | `~/.claude/settings.json` (installer) | Hook listener (loopback) | Claude calls hub; hub never exposed for it |

## Standard Stack

No new packages. Existing: `ws` 8.22.2, `node-pty` 1.1.0 (hub/package.json); Node >=22 (Mac has v22.20.0 at `/usr/local/bin/node` [VERIFIED: local `node --version`]); Tailscale 1.98.2 at `/usr/local/bin/tailscale` [VERIFIED: local].

Stdlib to use: `node:crypto` (`randomBytes`, `randomInt`, `createHash`, `timingSafeEqual`), `node:child_process.execFile`, `node:fs` (`realpathSync`, `statSync`), `node:net`/`http`, `node:os`.

### Package Legitimacy Audit
No external packages are added in this phase. slopcheck not run (nothing to check). `ws` and `node-pty` already installed in Phase 1.

**Packages removed due to slopcheck [SLOP] verdict:** none. **Flagged [SUS]:** none.

## Verified Facts (live on this Mac, 2026-11-11)

### Tailscale
- `tailscale ip -4` -> `100.125.215.102` (single line, exit 0). [VERIFIED: local]
- `tailscale whois --json <ip>` works for the phone IP and the Mac's own IP (self-whois succeeds, so a request originating on the Mac itself over the 100.x address passes whois). [VERIFIED: local]
- Field names (values redacted; all keys relevant to us): [VERIFIED: local]
  ```
  { "Node": { "ID", "StableID", "Name": "<host>.<tailnet>.ts.net." (trailing dot!),
              "User": <number>, "Addresses": ["100.x.y.z/32","fd7a:..../128"],
              "Hostinfo": {"OS":"iOS|(absent on self)","Hostname"}, "Online", "ComputedName": "iphone-14-pro-max",
              "KeyExpiry": "<RFC3339>", "Tags"?: [...] (only on tagged nodes, absent here) },
    "UserProfile": { "ID": <number>, "LoginName": "rishizamvar@icloud.com", "DisplayName": "rishizamvar" },
    "CapMap": null }
  ```
- Owner string to store/compare is `UserProfile.LoginName` = `<user>@icloud.com` format (full email). Do not hard-code; default `owner` = LoginName from the first successful `/pair` whois. Planner: CONTEXT's "current tailnet login is `rishizamvar@`" is the `tailscale status` short form, do not use it.
- Non-tailnet IP: `tailscale whois --json 8.8.8.8` -> stderr `peer not found`, **exit 1**, empty stdout. [VERIFIED: local] -> fail closed on any non-zero exit.
- Tagged node: `UserProfile` is absent/empty and `Node.Tags` present [ASSUMED from Tailscale docs/training; D-05 reject covers it: missing `UserProfile.LoginName` => 403].
- Tailscale stopped / not logged in: `tailscale ip -4` exits non-zero with a message such as "Tailscale is stopped." or "failed to connect to local tailscaled" [ASSUMED; web search found no authoritative text]. Contract for code: treat **non-zero exit OR empty stdout OR output not matching `/^100\.\d+\.\d+\.\d+$/`** as "no IP yet" -> backoff retry (D-02). Never parse error text.
- `KeyExpiry` on this Mac node = **2026-11-20T16:20:30Z**, phone = 2026-11-24 [VERIFIED: local whois]. When the hub node's key expires, tailnet listener silently dies. **Action: disable key expiry for the Mac node in Tailscale admin console now** (phone key expiry is independent but also needs a re-auth before 11-24 or the phone drops off the tailnet).
- `remoteAddress` pitfall: Node may report `::ffff:100.120.95.17` on dual-stack sockets; since we bind to the IPv4 100.x address it should be plain IPv4, but strip a `::ffff:` prefix defensively before whois and use only the IP (no port) as whois arg and cache key.

### launchd (macOS 26.6.2) [VERIFIED: `launchctl help` output + existing `~/Library/LaunchAgents/com.rishizamvar.*.plist` precedent]
- `launchctl bootstrap gui/$(id -u) <plist>`; `launchctl bootout gui/$(id -u)/<label>` (or with path); `launchctl kickstart -k gui/$(id -u)/<label>` (`-k` kills running instance first, `-p` prints pid). Legacy `load/unload` still exist but use bootstrap/bootout.
- Plist keys (standard, `plutil -lint` available at /usr/bin/plutil): `Label`, `ProgramArguments` (array: absolute node, absolute `hub/server.js`), `WorkingDirectory`, `RunAtLoad` true, `KeepAlive` true (use bare `<true/>`, not SuccessfulExit dict, so even exit 0 restarts), `ThrottleInterval` 10 (integer), `EnvironmentVariables` dict (`PATH`, optionally `HOME`), `StandardOutPath`/`StandardErrorPath`. [CITED: man launchd.plist; ASSUMED re exact semantics beyond help text]
- launchd agents get a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) so `claude` (`/Users/rishizamvar/.local/bin/claude` here [VERIFIED: `which claude`]) and tailscale must be injected via `EnvironmentVariables.PATH`; `resolveClaude()` in sessions.js must be checked to find claude under that PATH (or pass `ECHO_CLAUDE`-style override if it exists; planner: read `resolveClaude`).
- Re-install idempotency: `bootout` then `bootstrap` can race (bootstrap fails with "Bootstrap failed: 5: Input/output error" if the service is still tearing down). Use `launchctl bootout ... 2>/dev/null || true; sleep 1; launchctl bootstrap ...`, retry once. [ASSUMED from experience]
- No `~/.echo-hub/` collision: dir already exists (hub-hooks.json, sessions.json). No existing LaunchAgent named echo-hub.

### Claude Code http hooks [CITED: https://code.claude.com/docs/en/hooks]
- Settings shape = event -> array of matcher groups -> `hooks` array. Same shape as `writeHooksFile` in hooks.js: `{ "hooks": { "Stop": [ { "hooks": [ {type:"http", url, timeout, ...} ] } ] } }`. Omitted `matcher` = every occurrence.
- `http` hook fields: `type`, `url`, `headers`, `allowedEnvVars`, `timeout` (seconds; default 600 for http), plus `if`, `statusMessage`, `once`, `onFailure` (>= v2.1.295).
- **Failures are non-blocking by default**: connection refused, non-2xx, timeout, non-JSON 2xx body -> non-blocking error; Claude proceeds. Only `onFailure: "block"` makes them block. Never set it. Hub already answers `200` with empty body (empty 2xx = success). D-16's "hub down = Claude unaffected" is confirmed.
- A literal secret in the URL path is just a string; no interpolation needed. (Env interpolation is only for `headers`.) Works. [CITED docs for URL field; not live-tested, see Mac live check below]
- User `~/.claude/settings.json` hooks apply to all local sessions and merge with other levels; file edits are picked up by a file watcher (docs say "normally"), so running sessions may pick up the new hooks without restart; new sessions definitely do. `allowedHttpHookUrls` (if defined anywhere, e.g. managed policy) would block 127.0.0.1 URLs; this Mac's settings.json has no such key [VERIFIED: key list of settings.json: permissions, model, hooks, statusLine, enabledPlugins, ... no allowedHttpHookUrls].
- This Mac's settings.json `hooks` has only SessionStart/PostToolUse/PreToolUse (4/3/4 groups) and **no Stop/Notification** [VERIFIED: local]. Merge must create those keys; on PC they may exist -> append, never replace.
- Hub-owned sessions load BOTH the `--settings` per-process hooks and the global ones -> duplicate events. Global endpoint `/hook/ext/<secret>` must drop events whose `session_id` is in `sessions.ownedIds()` (D-16). Unknown ids already become "external" via `sessions.hook` (existing test 'unknown session_id -> external').

### URLSessionWebSocketTask + Authorization header (Phase 3 compatibility with D-08)
- `URLSession.webSocketTask(with: URLRequest)` takes a request whose headers are used for the HTTP upgrade handshake [CITED: developer.apple.com/documentation/foundation/urlsession/websockettask(with:)]. Setting `request.setValue("Bearer ...", forHTTPHeaderField: "Authorization")` is widely used and works in practice; Apple lists Authorization among headers "managed by the auth challenge mechanism", so behavior with `URLSessionConfiguration.httpAdditionalHeaders` is unreliable (reports it is dropped), but per-request setting is the supported path. [MEDIUM: no authoritative statement found; flagged]
- Recommendation: D-08 stands (header only, never query string). Phase 3 must set the header on the `URLRequest` itself and smoke-test it against this hub. Cheap insurance the planner may add: the hub also accepts `X-Echo-Token: <token>` as an equivalent header (still a header, never a query string). Not locked by CONTEXT; list as optional, default OFF unless Phase 3 test fails.

### Windows (docs/knowledge only; UNVERIFIED, PC offline) [ASSUMED unless noted]
D-15 parameter names (PowerShell ScheduledTasks module):
```powershell
$a = New-ScheduledTaskAction -Execute $node -Argument "`"$hub\server.js`"" -WorkingDirectory $hub
$t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$s = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
       -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
       -MultipleInstances IgnoreNew -StartWhenAvailable
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName echo-hub -Action $a -Trigger $t -Settings $s -Principal $p -Force
New-NetFirewallRule -DisplayName "echo-hub" -Direction Inbound -Action Allow -Protocol TCP `
       -LocalPort 8790 -RemoteAddress 100.64.0.0/10 -Profile Any   # requires elevated PowerShell
```
Notes: `-RestartInterval` minimum is 1 minute; `-ExecutionTimeLimit ([TimeSpan]::Zero)` = unlimited; `-LogonType Interactive` stores no password; the install script must self-check elevation (`[Security.Principal.WindowsPrincipal]...IsInRole(Administrator)`) because only the firewall rule needs admin (task registration for self does not). Direct `node.exe` action shows a console window; to hide, use `-Execute powershell.exe -Argument '-NoProfile -WindowStyle Hidden -Command "& ''node.exe'' ''server.js''; exit $LASTEXITCODE"'` (brief flash is acceptable; note UNVERIFIED). Unregister: `Unregister-ScheduledTask -TaskName echo-hub -Confirm:$false`; `Remove-NetFirewallRule -DisplayName echo-hub`. Deploy restart: `Stop-ScheduledTask`/`Start-ScheduledTask` (or `schtasks /End` + `/Run`).
Windows-specific: node-pty needs `claude.exe` path (Phase 1 concern); `npm ci` there needs build tools only if no prebuild.

## Architecture Patterns

### Request flow
```
phone --WireGuard--> 100.x:8790 [tailnet server] --> authTailnet(req)
                                   | whois(remoteIP) (60s cache, fail closed 403)
                                   | route=/health? -> 200 (no token)
                                   | route=/pair?   -> pairing (no token) 
                                   | else Bearer -> sha256 -> devices.json -> 401 | handler
CLI  --> 127.0.0.1:8790 [loopback server, ctx.tailnet=false] --> no auth, + /admin/* routes
Claude (hub-owned) --> 127.0.0.1:8791 /hook (X-Echo-Secret)
Claude (external)  --> 127.0.0.1:8791 /hook/ext/<secret> (path secret)
```

### File layout
```
hub/auth.js          # whois(), tailnetIp(), Devices (load/save/add/verify/revoke), Pairing (code, attempts), config load
hub/server.js        # makeHandler(ctx), two listeners, retry-bind, /health, /admin/*, /sessions/roots, cwd check, logger
hub/hooks.js         # + /hook/ext/<secret> route
hub/cli.js           # + pair | devices | revoke
hub/store.js         # save(file,obj,{mode}) -> writeFileSync mode 0o600
hub/install/         # install.sh uninstall.sh deploy.sh install.ps1 uninstall.ps1 deploy.ps1 (+ small node helper for settings.json merge)
hub/RUNBOOK.md
```
Settings.json merge: implement once as `hub/install/hooks-merge.js` (node, stdlib; `merge`/`unmerge` modes) called by both install.sh and install.ps1 (avoid `jq`/PowerShell JSON duplication; Windows PowerShell 5 JSON round-tripping mangles nested arrays/ordering). Backup to `settings.json.echo-bak` only if absent or differs (do not clobber the first backup on re-run). Write atomically (tmp + rename). Marker = url contains `/hook/ext/`.

### Key patterns
**Whois (auth.js)**
```js
const exec = promisify(execFile);
const cache = new Map(); // ip -> {ok, login, exp}
export async function whois(ip, {bin, ttl = 60000}) {
  ip = ip.replace(/^::ffff:/, '');
  const c = cache.get(ip); if (c && c.exp > Date.now()) return c.login;
  let login = null;
  try {
    const { stdout } = await exec(bin, ['whois', '--json', ip], { timeout: 3000, maxBuffer: 1 << 20 });
    login = JSON.parse(stdout)?.UserProfile?.LoginName || null;
  } catch {}               // non-zero, timeout, parse error -> fail closed
  if (login) cache.set(ip, { login, exp: Date.now() + ttl }); // ponytail: cache positives only; failures re-ask (cheap, avoids sticky outage)
  return login;
}
```
Cache positives only: a negative cache would lock out the phone for 60 s after a transient Tailscale hiccup. Add `timeout` on execFile (otherwise a hung CLI hangs requests). Cap the Map size (clear when > 100) or rely on tiny tailnet.

**Bearer verify**: `sha256(token)` -> look up by `Buffer.from(hash)` over devices with `timingSafeEqual` (equal-length hex digests, so length check never leaks). Update `lastSeen` in memory, persist at most every 60 s (avoid disk write per request).

**WS upgrade auth** (before `handleUpgrade`): `await authTailnet(req)`; on failure write `HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n` (403 for whois) and `sock.destroy()`. Because auth is async, attach an `error` handler on the socket first. Record `ws.deviceId` for revocation; `revoke()` iterates `wss.clients` and `ws.close(4401)`/`terminate()` for that deviceId.

**Two listeners + retry bind**: loopback `listen` immediately. Tailnet loop: `for (delay=1000;;delay=Math.min(delay*2,30000)) { ip = await tailnetIp(); if (ip) try { listen(port, ip); break } catch(EADDRNOTAVAIL/EADDRINUSE) {} ; await sleep(delay) }` run un-awaited so `startHub()` resolves after loopback is up (tests rely on this). Log only on state change. Also guard: assert bound IP matches `/^100\./` before listen and keep the existing grep gate ("0.0.0.0" must not appear). Remove the T-01-01 throw; replace with: `host` option is the loopback host (default 127.0.0.1, still never 0.0.0.0) and `tailnetIp` option (function or `ECHO_TAILNET_IP`) lets tests bind 127.0.0.1 on a second port. Consider re-checking `tailscale ip -4` if the tailnet server errors/closes (IP can change on re-auth): on `close`/`error` re-enter the loop.

**Pairing**: alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (Crockford, drops I L O U); 8 chars via `crypto.randomInt(32)` each (40 bits; single live code, 5 attempts, 5 min makes brute force infeasible). Normalize input: uppercase, strip spaces/hyphens, map `O->0`, `I/L->1`. Compare with `timingSafeEqual`. State: `{code, exp, name, attempts}`; success deletes it (single use); 5th wrong attempt deletes it; new `pair-code` replaces any live one. Attempt counter counts wrong tries across all remote IPs. Pair code response must not be cacheable by logs; never log the code (loopback CLI prints it only).

**cwd allowlist**: `realpathSync` both candidate and each root; allowed iff `rel = path.relative(root, real)` is not `..`-prefixed and not absolute (handles prefix confusion like `/Users/x/Projects-evil`). Defaults: Mac `[~/Documents/Projects, ~]`. Note root `~` allows everything under home including `~/.ssh`; that is the locked default (D-10) but flag in RUNBOOK. Apply the check on the tailnet AND loopback `POST /sessions` (single code path inside the handler) except keep the existing `bad_cwd` response code. Realpath of nonexistent path throws -> `bad_cwd`. `/sessions/roots`: for each root `readdirSync(withFileTypes)` directories only, skip dotfiles, cap (e.g. 200).

**Health**: `{ok:true, protocol:1, version, gitSha, uptime, os: process.platform, hubName: os.hostname()}`; keep `epoch` and `claude` fields Phase 1 tests/CLI use (additive). `gitSha`: `execFileSync('git',['rev-parse','--short=7','HEAD'],{cwd: hubDir})` in try/catch -> `unknown`. **`/Users/rishizamvar/Documents/Projects/echo.r2` is currently not a git repository** [VERIFIED: environment]. D-17 deploy assumes git; planner must either `git init` + remote as an explicit task/precondition or accept `unknown` and make deploy.sh fail with a clear message ("not a git checkout"). See Open Questions.

**Logger (D-18 conflict)**: launchd `StandardOutPath` holds an open fd; if the hub renames `hub.log` -> `hub.log.1`, launchd keeps writing to `.1` and the new `hub.log` stays empty. Fix: hub writes `~/.echo-hub/hub.log` itself via `fs.appendFileSync` (a 5-line `log(msg)` that stats size at startup and hourly, renames to `.1` if > 5 MB). Point launchd `StandardOutPath`/`StandardErrorPath` at a separate `launchd.log` for crash traces only (rarely grows). On Windows Task Scheduler there is no redirection, so the in-process logger is required anyway. Replace `console.log` in hub code with `log()`; never pass tokens/codes/headers.

### Anti-Patterns
- Reading the token from the query string (D-08) or logging `req.headers`.
- Binding `0.0.0.0` or `::`; falling back to it if no Tailscale IP.
- Negative-caching whois failures.
- Using `===` on hashes/codes.
- Rewriting `settings.json` with `JSON.stringify` of a partial object (must read-modify-write the whole file, preserving all other keys; key order will be preserved by JS object semantics).
- One shared handler that checks `req.socket.localAddress` to decide auth; use separate servers with a `tailnet` flag so loopback-only routes (`/admin/*`) cannot be reached by construction.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Peer identity | IP allowlist / own CIDR check | `tailscale whois --json` | Maps IP to login; CIDR proves nothing |
| Random codes/tokens | `Math.random` | `crypto.randomInt` / `randomBytes(32).toString('base64url')` | CSPRNG |
| Constant-time compare | `===` | `crypto.timingSafeEqual` on equal-length digests | Timing side channel |
| Atomic file write | direct writeFileSync | `store.save` (tmp+rename), extended with mode 0600 | Crash-safe, reuse Phase 1 |
| settings.json JSON surgery | sed/regex/jq | one node `hooks-merge.js` | Shared by both OS installers |
| Service supervision | own watchdog | launchd KeepAlive / Task Scheduler restart | OS already does it |
| Path containment | string `startsWith` | `realpath` + `path.relative` | Prefix and symlink bypass |

## Runtime State Inventory
Not a rename/refactor phase. Existing runtime state to be aware of: `~/.echo-hub/{hub-hooks.json,sessions.json}` (Phase 1, keep); new `config.json`, `devices.json`, `hub.log(.1)`, `launchd.log`; `~/.claude/settings.json` will be modified by the installer (backup `.echo-bak`). Nothing needs migration.

## Common Pitfalls

1. **Owner string mismatch.** `tailscale status` shows `rishizamvar@`; whois LoginName is `rishizamvar@icloud.com`. Default owner must come from whois at first pair, never typed by hand.
2. **Tailscale key expiry (9 days on Mac).** Hub tailnet listener stays dead / phone loses tailnet. Disable expiry for Mac node (and PC when it returns) in admin console; document in RUNBOOK and make it an install-checklist item. Optionally log a warning at startup if self `KeyExpiry` (from `tailscale whois --json <self ip>`) is < 14 days; low cost, high value.
3. **Hub-owned session fires global hooks too** -> duplicate state events. Drop via `ownedIds()` check on `/hook/ext/`.
4. **launchd log fd vs in-process rotation** (above).
5. **launchd minimal PATH.** claude/tailscale/git not found. Set `EnvironmentVariables.PATH`; hub's `ECHO_TAILSCALE` default resolution (D-03) uses absolute paths so tailscale is fine, but `claude`, `git` (gitSha) need PATH.
6. **macOS TCC for `~/Documents`.** Repo lives under `~/Documents/Projects`; a launchd-started `node` reading/spawning there may hit Files & Folders (Documents) privacy prompts/denials that Terminal-launched processes avoid. [ASSUMED] First start from launchd may prompt once (or silently EPERM). Mac live check must start via launchd and create a session in `~/Documents/Projects/...`. Mitigation if denied: grant `/usr/local/bin/node` Full Disk Access (or Files & Folders), or move the checkout. Put this in RUNBOOK.
7. **Mac sleep** makes hub unreachable (accepted D-14). Note: Tailscale's 100.x listener survives wake without restart; retry-loop only matters if IP changes.
8. **`launchctl bootout`->`bootstrap` race** (retry once).
9. **WS auth is async**: events can arrive on the socket before the check resolves; buffer is fine because `handleUpgrade` is only called after success, but you must `sock.on('error', ()=>{})` to avoid uncaught errors on early client disconnect.
10. **`/pair` abuse before token exists**: whois + code attempts limit is the only guard; keep the 5-attempt invalidation global, and make `/pair` with no live code return 403 `no_code` (same body whether expired or wrong, to avoid oracle).
11. **Windows (parked):** firewall rule needs elevation; `-RestartInterval` >= 1 min; hidden window; auto-logon absent means no hub until Rishi logs in; Tailscale may start after the task (retry loop covers). All UNVERIFIED until PC returns.
12. **Global hook timeout.** Use `timeout: 3` (seconds). Default for http is 600 — a hung hub would otherwise stall Claude's Stop. Connection refused returns immediately.
13. **Existing CLI** (`cli.js`) uses plain `fetch` to loopback: keep working because loopback has no auth. `api()` assumes JSON on every response — `pair` must return JSON `{code, expiresIn}`.
14. **Not a git repo** -> deploy/gitSha (Open Question 1).

## Code Examples

### settings.json hook entry (D-16)
```json
{ "hooks": { "Stop": [ { "hooks": [ { "type": "http", "url": "http://127.0.0.1:8791/hook/ext/<random>", "timeout": 3 } ] } ],
             "Notification": [ { "hooks": [ { "type": "http", "url": "http://127.0.0.1:8791/hook/ext/<random>", "timeout": 3 } ] } ] } }
```
Merge: for each event, `arr = (settings.hooks[event] ??= [])`; remove any group whose `hooks[*].url` includes `/hook/ext/`, then push the new group (idempotent, updates secret/port). Unmerge: filter those out; delete event key only if the array becomes empty and the hooks object had no other content for it.

### launchd plist (D-13) skeleton
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.rishizamvar.echo-hub</string>
  <key>ProgramArguments</key><array><string>/usr/local/bin/node</string><string>/abs/hub/server.js</string></array>
  <key>WorkingDirectory</key><string>/abs/hub</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>...</string></dict>
  <key>StandardOutPath</key><string>/Users/.../.echo-hub/launchd.log</string>
  <key>StandardErrorPath</key><string>/Users/.../.echo-hub/launchd.log</string>
</dict></plist>
```
Generate via heredoc in install.sh with values from `command -v node`, `$(cd "$(dirname "$0")/.." && pwd)`; run `plutil -lint` before bootstrap. `install.sh` commands: `launchctl bootout gui/$UID/$LABEL 2>/dev/null; sleep 1; launchctl bootstrap gui/$UID "$PLIST"` (retry once); `uninstall.sh`: bootout, rm plist, run `hooks-merge.js unmerge`.

### deploy.sh poll
```sh
old=$(git rev-parse --short=7 HEAD); git pull --ff-only; new=$(git rev-parse --short=7 HEAD)
(cd hub && npm ci --omit=dev)
launchctl kickstart -k gui/$UID/com.rishizamvar.echo-hub
for i in $(seq 30); do curl -fs http://127.0.0.1:8790/health | grep -q "\"gitSha\":\"$new\"" && { echo "deployed $new"; exit 0; }; sleep 1; done
echo "deploy FAILED"; exit 1
```
Use `set -e` and the same `--short=7` in server.js so the comparison is stable.

## State of the Art
| Old | Current | Impact |
|-----|---------|--------|
| `launchctl load/unload` | `bootstrap/bootout/kickstart` | Use new verbs |
| command hooks with curl | `type:"http"` hooks | No curl dependency; non-blocking failures |
| Node `ws` needed for WS | still true for server | keep `ws` |

## Assumptions Log
| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `tailscale ip -4` when stopped exits non-zero with text message | Verified Facts | Low: code treats anything not 100.x as "no IP" |
| A2 | Tagged nodes lack `UserProfile` | Verified Facts | Low: missing LoginName rejected either way |
| A3 | Per-request `Authorization` header reaches server on `URLSessionWebSocketTask` | iOS | Phase 3 breakage; mitigated by optional `X-Echo-Token` |
| A4 | launchd-started node may hit TCC for `~/Documents` | Pitfalls | Hub can't read repo/projects; needs FDA or repo move |
| A5 | bootout->bootstrap race returns error 5 | launchd | Re-install flakiness; retry handles |
| A6 | Windows cmdlet parameter names/behaviors, hidden-window approach | Windows | PC checkpoint finds fixes; parked anyway |
| A7 | Claude hooks hot-reload from settings.json watcher | Hooks | Existing sessions need restart to report; docs say "normally" picks up |

## Open Questions (RESOLVED)
1. **Repo is not a git repository** (`echo.r2` has no `.git`). D-17 deploy and `gitSha` need one. Recommendation: Wave 0 task `git init` + commit (user's call on a remote); deploy.sh errors clearly if `git rev-parse` fails. `gitSha` falls back to `unknown` per D-12 so nothing else blocks.
   RESOLVED: the repo IS a git checkout (origin rishi-zamvar/echo.r2, private) per D-21 and verified at planning (`git rev-parse --short HEAD` works). No git init task; deploy.sh still fails clearly with `not a git checkout` as a guard.
2. **Should `Notification` global hook also be restricted by matcher?** Default (no matcher) fires for all notification types; consistent with hub-owned file. Keep.
   RESOLVED: no matcher (all notification types), same as the hub-owned hooks file. Related: the optional `X-Echo-Token` header fallback for URLSessionWebSocketTask is deferred to the Phase 3 on-device smoke test; D-08 (Authorization: Bearer only) stands for Phase 2.
3. **Does `resolveClaude()` honor PATH at launchd time?** Planner reads `sessions.js resolveClaude`; if it only checks fixed locations, fine; if PATH-based, the plist PATH must include `~/.local/bin`.
   RESOLVED: resolveClaude() on darwin is PATH-based (`sh -c 'command -v claude'`), so install.sh puts the resolved claude dir (dirname of `command -v claude`, here ~/.local/bin) in the plist EnvironmentVariables.PATH per D-21; 02-06 L5 proves it live.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| node | hub, installers | yes | v22.20.0 (/usr/local/bin/node) | — |
| tailscale CLI | whois/ip | yes | 1.98.2 (/usr/local/bin/tailscale) | `ECHO_TAILSCALE` |
| launchctl / plutil | install.sh | yes | macOS 26.6.2 | — |
| claude | sessions | yes | /Users/rishizamvar/.local/bin/claude | — |
| git | deploy/gitSha | binary likely; **repo not initialized** | — | gitSha `unknown` |
| PC (zee-cloud) | Windows verify | no (offline ~1 month) | — | park as PC checkpoint |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `node:test` + `node:assert` (existing) |
| Config file | none; `hub/package.json` `"test": "node --test hub.test.js"` |
| Quick run | `cd hub && node --test hub.test.js` |
| Full suite | same (single file, ~existing 20+ tests) |

### Test seam
`ECHO_TAILSCALE` env (or `tailscale` startHub option) -> a fake executable generated in a tmp dir by the test (`#!/bin/sh` script; use the existing `posix` skip flag for Windows). The fake handles `ip -4` (prints a configurable IP, e.g. `127.0.0.1`, so the tailnet listener binds loopback on a second ephemeral port) and `whois --json <ip>` (reads a tmp file for JSON/exit code so tests can switch identity, fail, or hang). Add startHub options `tailnetPort` (default = `port`; tests use 0) and `configDir` = `dataDir`. Tests send requests to the tailnet listener from 127.0.0.1 so whois ip = `127.0.0.1` (fake keyed on that).

### Phase Requirements -> Test Map
| Req | Behavior | Type | Command | Exists |
|-----|----------|------|---------|--------|
| HUB-02 | whois non-zero / bad JSON / wrong login / missing UserProfile -> 403; owner OK -> pass | unit+integ | `node --test --test-name-pattern whois hub.test.js` | Wave 0 |
| HUB-02 | 0.0.0.0 never bound; source grep gate | unit | `--test-name-pattern bind` (extends 'loopback bind') | partial |
| HUB-02 | no Tailscale IP -> loopback up, tailnet retries then binds when fake starts printing IP | integ | `--test-name-pattern retry` (use small backoff via option) | Wave 0 |
| HUB-03 | `/health` fields incl. gitSha (fallback `unknown`) on both listeners; tailnet needs whois not token | integ | `--test-name-pattern health` | Wave 0 |
| AUTH-01 | pair-code: 8 chars alphabet, single use, expires (inject clock/ttl option), only one live, 5 wrong invalidates, `/pair` returns 201 token | integ | `--test-name-pattern pair` | Wave 0 |
| AUTH-01 | devices.json contains hash not token, mode 600 | unit | `--test-name-pattern devices` | Wave 0 |
| AUTH-01/D-08 | missing/invalid bearer -> 401 JSON; WS upgrade without bearer -> 401 before handshake; token in query ignored | integ | `--test-name-pattern bearer` | Wave 0 |
| AUTH-03 | revoke -> next request 401; open WS for that device closed | integ | `--test-name-pattern revoke` | Wave 0 |
| D-10/11 | cwd outside roots, symlink escape, prefix sibling -> 400 bad_cwd; `/sessions/roots` lists subdirs | integ | `--test-name-pattern cwd` | Wave 0 |
| D-01 | `/admin/*` on tailnet listener with a VALID token -> exactly 404 | integ | `--test-name-pattern admin` | Wave 0 |
| D-01 | loopback rejects foreign Host / any Origin -> 403 (DNS rebinding) | integ | `--test-name-pattern loopback` | Wave 0 |
| D-05 | whois 'tagged-devices' / missing UserProfile -> rejected even without owner | unit | `--test-name-pattern tagged` | Wave 0 |
| D-16 | `hooks-merge.js`: idempotent, preserves other hooks, backup made, unmerge removes only marked, run against tmp settings file | unit | `--test-name-pattern merge` | Wave 0 |
| D-16 | `/hook/ext/<secret>` bad secret 404/403; owned id ignored; unknown -> external | integ | `--test-name-pattern ext hook` | Wave 0 |
| D-18 | log rotates at threshold (inject small max), no token in log | unit | `--test-name-pattern log` | Wave 0 |
| HUB-01/04 | plist generation `plutil -lint` passes (posix/darwin only); `install.sh` has no unguarded destructive ops | smoke | `plutil -lint <generated plist>` | Wave 0 |

### Mac live checks (manual/scripted, executed this phase)
1. `install.sh` -> `launchctl print gui/$UID/com.rishizamvar.echo-hub` shows running; `curl 127.0.0.1:8790/health` ok; `curl http://100.125.215.102:8790/health` from the Mac itself ok (self whois passes); `kill -9 <pid>` -> back within ~10-15 s.
2. Start from launchd, `cli.js new ~/Documents/Projects/<x>` works (TCC check, pitfall 6).
3. `cli.js pair` -> from the phone (or `curl --interface`/from the Mac over the 100.x address with a pair POST) get token; `GET /sessions` with and without bearer; `cli revoke` -> 401.
4. Install merged hooks: backup exists, existing SessionStart/PreToolUse/PostToolUse untouched (diff), run `claude -p "hi"` externally with hub stopped (proves no blocking) and with hub running (session appears external). `uninstall.sh` restores equivalent settings.
5. Confirm Tailscale key expiry disabled for the Mac node (whois `KeyExpiry` absent/zero or console).
6. `deploy.sh` after `git init` (Open Question 1).
7. Log: `hub.log` written by hub; launchd.log empty-ish.

### PC deferred checks (parked, like 01-05/01-06)
`install.ps1` registers task (`Get-ScheduledTask echo-hub`), firewall rule scoped to 100.64.0.0/10, reboot/logon starts hub, kill node -> restarts within ~1 min, hidden window, `deploy.ps1` round trip, Tailscale path `C:\Program Files\Tailscale\tailscale.exe`, whois field names on PC, claude.exe spawn. Record in a PC checkpoint plan.

### Sampling Rate
- Per task commit: `cd hub && node --test hub.test.js` (target < 30 s)
- Phase gate: full suite green + Mac live checks 1-7 recorded.

### Wave 0 Gaps
- [ ] fake-tailscale helper + new tests in `hub/hub.test.js`
- [ ] startHub options for tests: `tailnetPort`, `tailscale`/`ECHO_TAILSCALE`, `retry` backoff base, pair TTL/clock, `maxLogBytes`
- [ ] `git init` decision (Open Question 1)

## Security Domain

### Applicable ASVS Categories
| Category | Applies | Control |
|----------|---------|---------|
| V2 Authentication | yes | One-time pair code (CSPRNG, 5 min, 5 attempts) + 256-bit bearer token, hashed at rest |
| V3 Session Mgmt | partial | Long-lived device token, revocable; WS closed on revoke |
| V4 Access Control | yes | whois owner check + token; `/admin/*` loopback-only listener; cwd allowlist |
| V5 Input Validation | yes | JSON body size cap (existing 1 MB), code normalization, realpath containment, id regexes |
| V6 Cryptography | yes | `node:crypto` only; no custom primitives |
| V7 Logging | yes | Never log tokens, codes, Authorization, transcripts |

### Known Threat Patterns
| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Other tailnet user/device (shared node, tagged device) calling hub | Spoofing | whois LoginName == owner; tagged -> reject; recommended ACL phone->hub:8790 |
| Brute-forcing pair code | Spoofing | 40-bit code, single use, 5 attempts invalidate, 5 min TTL |
| Token theft from disk | Info disclosure | Only SHA-256 stored; devices.json 0600 |
| Timing attacks | Info disclosure | `timingSafeEqual` |
| Local user/process hitting loopback admin | Elevation | Loopback unauthenticated by design (D-01): any local process can mint a pair code; accepted single-user machine, note in RUNBOOK |
| cwd traversal / symlink escape -> RCE scope | Tampering/EoP | realpath + relative containment; never `--dangerously-skip-permissions` |
| Secret in global hook URL leaking | Info disclosure | Loopback only, random 128-bit, settings.json is user-readable only (`chmod 600` after merge on Mac) |
| WS hijack via query-string token | Spoofing | Header only |
| Whois CLI argument injection | Tampering | `execFile` (no shell), IP validated against `net.isIP` before use |
| Exposure on LAN/public | Info disclosure | Bind to 100.x only; PC firewall rule 100.64.0.0/10 |

## Sources
### Primary (HIGH)
- Local verification on this Mac: `tailscale ip -4`, `tailscale whois --json` (phone, self, non-peer), `launchctl help bootstrap|kickstart|bootout`, `settings.json` key inspection, `which claude/node`
- https://code.claude.com/docs/en/hooks - settings shape, http hook fields, failure semantics, scope, `allowedHttpHookUrls` (only first 100k of 293k chars read)
### Secondary (MEDIUM)
- Apple docs `URLSession.webSocketTask(with:)` + Apple Developer Forums thread 784461 (Authorization is "reserved"; per-request header practice) via web search
### Tertiary (LOW)
- Tailscale stopped-state message/exit code (forum search found nothing authoritative); Windows cmdlet details (training knowledge); launchd TCC behavior (training knowledge)

## Metadata
**Confidence:** Standard stack HIGH (no new deps); Architecture HIGH; Mac install HIGH; Windows MEDIUM-LOW (unverified by design); iOS header MEDIUM.
**Research date:** 2026-11-11 | **Valid until:** ~30 days (Claude Code hooks fast-moving; recheck `onFailure`/http hook docs at implementation)
