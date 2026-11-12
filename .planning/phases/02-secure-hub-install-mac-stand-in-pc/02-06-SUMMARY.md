---
phase: 02-secure-hub-install-mac-stand-in-pc
plan: 06
subsystem: hub-install
tags: [launchd, tailscale, auth, live-verification]
requires: [02-04, 02-05]
provides: ["Mac stand-in hub installed and running under launchd, evidenced in RUNBOOK"]
affects: [hub/RUNBOOK.md]
key-files:
  modified: [hub/RUNBOOK.md]
decisions: []
metrics:
  completed: 2026-11-11
---

# Phase 2 Plan 06: Mac live verification Summary

The hub runs as a launchd LaunchAgent on this Mac (loopback plus 100.125.215.102:8790 only), restarts in 1 s after kill -9, and every auth status code in the pair/revoke sequence matched the plan.

login autostart not proven until next real login (check `curl -s 127.0.0.1:8790/health` after it).

## Results (commit 9b0ece5, docs(02-06): mac live verification)

- L1 PASS: plist RunAtLoad=true, KeepAlive=true, job running. Minor: hub.log is 0644, not 0600 (config.json and devices.json are 0600).
- L2 PASS: restart in 1 s, new pid.
- L3 PASS: gitSha 500e625 on loopback and tailnet; listeners only 127.0.0.1:8790, 127.0.0.1:8791, 100.125.215.102:8790.
- L4 PASS: 401, 403, 201, 200, 404, 403, 403, 401 in the required order; mac-curl revoked; token not in hub.log or devices.json.
- L5 PARTIAL (see Gaps).
- L6 PASS: only Stop/Notification hooks added; `claude -p` fine with hub down; re-install byte-identical; external session visible with hub up.
- L7 PASS: `deployed 500e625`.
- L8 PASS: Mac KeyExpiry 2027-05-11 (renewed by Rishi). The phone key (2026-11-24) is still open.

## Deviations from Plan

None to code. Task 1/2 and the install were completed by a previous agent run.

## Gaps

- L5: launchd hub launched real Claude in ~/Documents/Projects/echo.r2, proving TCC and PATH, but Claude's folder-trust dialog blocked the "pong" answer and hub CLI `send` cannot navigate it. Rishi: run `claude` once in echo.r2, accept trust, then re-run `node hub/cli.js new ~/Documents/Projects/echo.r2 "reply with the single word pong"`.
- hub.log permissions 0644 (hub.log contains no tokens); consider chmod 600 in a gap plan.
- Hook secret was accidentally printed to the agent transcript during L5 troubleshooting (not committed). Rotate by editing hookSecret in ~/.echo-hub/config.json and re-running install.sh if that matters.

## Known Stubs

None.

## Self-Check: PASSED

Commit 9b0ece5 exists; RUNBOOK contains "Verified on Mac"; hub installed and running; mac-curl revoked.
