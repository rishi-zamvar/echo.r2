---
phase: 02-secure-hub-install-mac-stand-in-pc
plan: 01
subsystem: hub
tags: [tailscale, whois, security, health]
requires: []
provides: [hub/auth.js, tailnet listener, /health full payload]
affects: [02-02]
tech-stack:
  added: []
  patterns: [two http.Server sharing one handler factory, retry-bind loop, fail-closed whois]
key-files:
  created: [hub/auth.js, hub/fixtures/fake-tailscale.mjs]
  modified: [hub/server.js, hub/store.js, hub/hub.test.js]
decisions:
  - "Added test-only startHub option whoisTtlMs (default 60000) so tests can change identity without waiting out the cache"
requirements-completed: [HUB-02, HUB-03]
duration: ~15min
completed: 2026-11-11
---

# Phase 2 Plan 01: Tailnet listener + whois gate + /health Summary

Hub now binds loopback plus the Tailscale IPv4 (retry with backoff), gates every tailnet request on `tailscale whois` (fail closed, tagged nodes rejected), answers 401 for everything but /health on the tailnet, and guards loopback against foreign Host/Origin.

## Commits
- db9a406: test(02-01): failing tailnet/whois/health tests (RED; suite failed on missing auth.js import)
- 930b070: feat(02-01): tailnet listener with whois gate and /health (GREEN; 34 pass, 0 fail)

## Smoke (Mac, real Tailscale, port 18790)
- loopback /health: 200, gitSha db9a406 (matches `git rev-parse --short=7 HEAD`)
- loopback with Origin header: 403
- http://100.125.215.102:18790/health: 200 (self-whois); /sessions: 401
- process killed afterwards

## Deviations from Plan
- [Rule 3] Added `whoisTtlMs` startHub option (test seam); the plan's 60 s positive cache otherwise masked identity changes in 'whois fail closed'. Default unchanged.
- RED state: the 26 pre-existing tests could not report as passing because the test file imports the not-yet-existing auth.js; whole file failed to load.

## Known Stubs
None. Tailnet 401 for non-/health routes is intentional until Plan 02 adds bearer auth.

## Self-Check: PASSED
