# Echo hub runbook

Commands run from the repo root. Data dir: `~/.echo-hub` (override `ECHO_DATA_DIR`).

## Install (Mac)

    sh hub/install/install.sh

Changes: LaunchAgent `~/Library/LaunchAgents/com.rishizamvar.echo-hub.plist` (RunAtLoad, KeepAlive, ThrottleInterval 10); global Claude hooks are OFF by default because Even Terminal shares `~/.claude/settings.json`: hub-owned sessions get hooks via `--settings`, external alerts come from the transcript, and `--global-hooks` (`-GlobalHooks` on PC) re-enables the old merge into `settings.json` (first backup kept as `settings.json.echo-bak`); `~/.echo-hub` created mode 700. `sh hub/install/install.sh --dry-run` prints the plist and changes nothing.

Check:

    launchctl print gui/$(id -u)/com.rishizamvar.echo-hub | grep state
    curl -s 127.0.0.1:8790/health

## Pair

Do this immediately after install: the first pair sets the owner login.

    node hub/cli.js pair iphone

Enter the code in the app within 5 minutes.

Zero-tap: `POST /pair/auto {deviceName}` on the tailnet listener mints a token with no code, only when an owner is already set (by a code pair) and whois shows that owner on an untagged node. Max 5 per 10 minutes. Revoking an auto-paired device adds its Tailscale node to `autoPairDeny` in config.json, so it cannot auto-pair again; a code pair from that node clears the entry.

## Devices and revoke

    node hub/cli.js devices
    node hub/cli.js revoke <id8|name>

## Deploy

    sh hub/install/deploy.sh

Prints `deployed <sha>` once /health reports the new gitSha. On `deploy FAILED`, read the logs.

## Push (APNs)

Add to `~/.echo-hub/config.json`: `"apns": {"keyId": "<KEYID>", "teamId": "373D7DZ9NM", "bundleId": "com.rishizamvar.echor2"}` (optional `keyPath`; default is the key below).
Put the key at `~/.echo-hub/AuthKey_<keyId>.p8`, mode 600. Never commit it; back it up in the password manager.
Restart: `launchctl kickstart -k gui/$(id -u)/com.rishizamvar.echo-hub`.
Verify: `curl -s 127.0.0.1:8790/health` shows `"push":"ready"`, then `node hub/cli.js test-push` (exits non-zero with `push_unconfigured` until the key is set).

## Resume / take over

- `node hub/cli.js resume <id>`: bring back a stopped (hub restarted) or exited hub session under the same id (`claude --resume`).
- `node hub/cli.js takeover <id>`: pull an external session into the hub (writable). Refused with `409 busy` while its transcript changed in the last 60 s or a live claude process has it: stop it on the other device first, then retry.
- Both re-check the cwd allowlist (`400 bad_cwd` outside the roots).

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
