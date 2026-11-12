---
phase: 04-push-recovery-release
plan: 01
subsystem: hub
tags: [apns, push, http2, jwt]
requires: []
provides:
  - hub/apns.js (makeJwt, alertText, apnsRequest, http2Send, Push)
  - Devices.setPush / dropPush / pushTargets
  - POST /devices/push, POST /devices/push/test, POST /admin/test-push, health.push
affects: [04-02, 04-04, 04-05]
tech-stack:
  added: []
  patterns: [injectable send fn (apnsSend) for stub APNs in tests]
key-files:
  created: [hub/apns.js]
  modified: [hub/auth.js, hub/server.js, hub/cli.js, hub/hub.test.js]
key-decisions:
  - "Push.alert sends immediately; 04-02 adds the per-session cooldown"
  - "Retry-once is immediate (no backoff)"
requirements-completed: [NOTF-03, NOTF-05]
duration: 15min
completed: 2026-11-12
---

# Phase 4 Plan 1: APNs push foundation Summary

Stdlib-only APNs sender (ES256 JWT, per-env host routing, retry-once, stale-token cleanup) with device-bound token registration, test-push routes/CLI, and a hub-started push on first tailnet bind.

## Commits
- 893c581 test(04-01): failing tests (RED)
- 90a5584 feat(04-01): implementation (GREEN)

## Verification
`cd hub && node --test hub.test.js` -> `# pass 55` / `# fail 0` (six new tests included). No new deps; apns.js imports only node: builtins.

## Deviations from Plan
None - plan executed as written.

## Known Stubs
None. Real APNs delivery is unexercised until the .p8 key is placed (D-15); tests use a stub sender.

## Self-Check: PASSED
