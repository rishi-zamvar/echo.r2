# Echo hub runbook

Commands run from the repo root. Data dir: `~/.echo-hub` (override `ECHO_DATA_DIR`).

## Install (Mac)

    sh hub/install/install.sh

Changes: LaunchAgent `~/Library/LaunchAgents/com.rishizamvar.echo-hub.plist` (RunAtLoad, KeepAlive, ThrottleInterval 10); Stop/Notification http hooks merged into `~/.claude/settings.json` (first backup kept as `settings.json.echo-bak`); `~/.echo-hub` created mode 700. `sh hub/install/install.sh --dry-run` prints the plist and changes nothing.

Check:

    launchctl print gui/$(id -u)/com.rishizamvar.echo-hub | grep state
    curl -s 127.0.0.1:8790/health

## Pair

Do this immediately after install: the first pair sets the owner login.

    node hub/cli.js pair iphone

Enter the code in the app within 5 minutes.

## Devices and revoke

    node hub/cli.js devices
    node hub/cli.js revoke <id8|name>

## Deploy

    sh hub/install/deploy.sh

Prints `deployed <sha>` once /health reports the new gitSha. On `deploy FAILED`, read the logs.

## Logs

- `~/.echo-hub/hub.log` (plus `.1`, 5 MB rotation): hub log, never contains tokens.
- `~/.echo-hub/launchd.log`: stdout/stderr, crash traces only.

## Uninstall

    sh hub/install/uninstall.sh

Boots out the agent, removes the plist, removes only Echo hook entries. Data is kept.

## Tailscale key expiry

Node keys expire (Mac `rishis-macbook-pro`: 2026-11-20). Disable key expiry for `rishis-macbook-pro` (and `zee-cloud` when it returns) at https://login.tailscale.com/admin/machines, machine menu, Disable key expiry. Verify:

    tailscale whois --json $(tailscale ip -4) | grep KeyExpiry

The phone key (2026-11-24) needs a re-auth or the same toggle.

## Tailscale ACL (recommended, not applied automatically)

Only the owner's devices should reach the hub on tcp:8790:

    {"acls":[{"action":"accept","src":["<owner-login>"],"dst":["<hub-host>:8790"]}]}

## Mac caveats

- Sleep means the hub is unreachable (accepted, no pmset or caffeinate).
- macOS TCC: if launchd.log shows EPERM and the repo is under `~/Documents`, grant Full Disk Access (or Files and Folders, Documents) to the node binary from `command -v node`.

## Security notes

- Loopback 127.0.0.1:8790 is unauthenticated admin by design: any local process can mint a pair code.
- Tagged Tailscale nodes are rejected (no user login).
- Default root `~` lets sessions start anywhere in home, including `~/.ssh`. Narrow `roots` in `~/.echo-hub/config.json` if wanted.
- The owner login lives in config.json (`owner`); delete it and re-pair to reset.

## PC (Windows, UNVERIFIED until the PC returns)

Elevated PowerShell:

    powershell -ExecutionPolicy Bypass -File hub\install\install.ps1

Also `deploy.ps1` and `uninstall.ps1`. Firewall rule `echo-hub` scoped to 100.64.0.0/10.

## PC-return checklist

1. PC appears in `tailscale status`.
2. Resume 01-05 Task 3 and 01-06 (Phase 1 PC spikes/acceptance).
3. Execute 02-07 (Phase 2 PC checks).
4. Disable key expiry for `zee-cloud`.
5. Pair the phone against the PC hub.

## Verified on Mac

2026-11-11, SHA 500e625, host rishis-macbook-pro (100.125.215.102).

- L1 PASS: LaunchAgent loaded, state running, RunAtLoad=true, KeepAlive=true. Minor: hub.log is 0644 (config.json, devices.json 0600). Login autostart not proven until next real login.
- L2 PASS: kill -9, launchd restarted hub with new pid in 1 s.
- L3 PASS: loopback and tailnet /health both gitSha 500e625; hub listens only on 127.0.0.1:8790, 127.0.0.1:8791, 100.125.215.102:8790 (no wildcard).
- L4 PASS: 401 no token, 403 wrong code, 201 pair, 200 bearer, 404 tailnet /admin/devices, 403 loopback bad Origin, 403 code reuse, 401 after revoke; owner recorded; token absent from hub.log and devices.json.
- L5 PARTIAL: launchd hub spawned real Claude in ~/Documents/Projects/echo.r2 (TCC and PATH OK) but Claude's one-time folder trust dialog blocked the "pong" and the hub CLI cannot answer it. Fix: run `claude` once in the folder and accept trust, then repeat `node hub/cli.js new <dir> "reply with the single word pong"`.
- L6 PASS: settings.json equals backup apart from Stop/Notification hooks; `claude -p` works with hub down (4 s); re-install is byte-identical; `claude -p` with hub up appears as external.
- L7 PASS: deploy.sh printed `deployed 500e625` = HEAD.
- L8 PASS: KeyExpiry for the Mac is now 2027-05-11 (was 2026-11-20).
