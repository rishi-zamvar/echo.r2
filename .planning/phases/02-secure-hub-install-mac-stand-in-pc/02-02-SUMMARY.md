---
phase: 02-secure-hub-install-mac-stand-in-pc
plan: 02
subsystem: hub
tags: [auth, pairing, bearer, revoke]
requires: [02-01]
provides: [Pairing, Devices, /pair, bearer gate, /admin/* loopback routes, cli pair/devices/revoke]
affects: [02-03, 02-04]
tech-stack:
  added: []
  patterns: [shared routes() behind two gates, admin routes dispatched only by loopback handler, sha256-at-rest tokens]
key-files:
  created: []
  modified: [hub/auth.js, hub/server.js, hub/cli.js, hub/hub.test.js]
decisions:
  - "Single `same()` helper wraps timingSafeEqual (length-checked) for both code and token hash compares"
requirements-completed: [AUTH-01, AUTH-03, HUB-02]
duration: ~20min
completed: 2026-11-11
---

# Phase 2 Plan 02: Pairing, bearer tokens, revoke Summary

One-time 8-char pair code (5 min, single use, 5 wrong attempts burn it) exchanges over the tailnet for a per-device bearer token stored only as SHA-256 (devices.json, mode 600); every tailnet route and WS upgrade needs the Authorization header, and revoke from the loopback CLI cuts HTTP and closes open sockets with 4401.

## Commits
- df8eca1: test(02-02): failing pair/bearer/revoke tests (RED: suite failed to load, Pairing not exported)
- 6792882: feat(02-02): pairing, bearer tokens, revoke (GREEN: 41 pass, 0 fail)
- 0acb071: feat(02-02): cli pair, devices, revoke

## Smoke (Mac, real Tailscale 100.125.215.102:18790, temp data dir)
- `cli.js pair smoke` -> `XXXX-XXXX  expires 18:31` (format matches)
- POST /pair -> 201 {token <redacted>, deviceId}
- `cli.js devices` -> `85ad3d7c smoke 2026-11-11 -`
- authed GET /sessions -> 200; `cli.js revoke smoke` -> `revoked 1`; same request -> 401
- hub killed, nothing left running

## Deviations from Plan
- [Minor] `grep -c timingSafeEqual hub/auth.js` is 1, not >= 2: both comparisons go through one `same()` helper instead of duplicating the call. Intent (constant-time compare everywhere, no `===` on secrets) holds; the `===` grep gate returns nothing.
- The console grep gate matches one pre-existing line (`e.code === 'EADDRINUSE'` in server.js startup error); it logs no secret.
- `whoisTtlMs` option already existed from 02-01; no change needed.
- Added `return await` on dispatched async handlers so rejections hit the handler's 500 catch.

## Known Stubs
None.

## Self-Check: PASSED
