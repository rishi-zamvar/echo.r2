---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 05
subsystem: hub
tags: [pairing, apns, whois]
requires: [05-04]
provides: [POST /pair/auto, config.autoPairDeny, pushMessage, health.pushLastError, push test result message]
affects: [hub/auth.js, hub/apns.js, hub/server.js, hub/hub.test.js, hub/RUNBOOK.md]
key-files:
  modified: [hub/auth.js, hub/apns.js, hub/server.js, hub/hub.test.js, hub/RUNBOOK.md]
decisions:
  - "whois.detail(ip) returns {login, node}; whois(ip) still returns the login string, so no caller changes"
  - "Auto-pair rate limiter is a single global in-memory list (ponytail comment)"
metrics:
  tasks: 2
  completed: 2026-11-12
---

# Phase 5 Plan 05: Zero-tap pairing and readable push errors Summary

`POST /pair/auto` (tailnet listener only, owner-only, untagged, revoke-safe deny list, 5 per 10 min) and plain-language APNs messages in `/devices/push/test` results and `/health.pushLastError`. Deployed to the live Mac hub.

## Commits
- c0b44ad: feat(05-05): both tasks in one commit (shared files server.js and hub.test.js)

## Verification
- `cd hub && node --test hub.test.js`: `# pass 84`, `# fail 0` (77 baseline + 7 new, 5 with `auto` in the name)
- `node hub/tools/safety-harness.mjs 50`: `safety ok 50 restarts, 0 external kills`
- `sh hub/install/deploy.sh`: `deployed c0b44ad`; live `/health` gitSha `c0b44ad` and contains `pushLastError` (currently a populated 403 error from the hub's startup push, which is the BadEnvironmentKeyInToken case that 05-12 fixes).

## Deviations from Plan
- Single commit for both tasks.
- `Devices.add(name, autoNode)` takes an optional node; `pair()` also saves config only when owner or deny list changed.

## Known Stubs
None.

## Self-Check: PASSED
