---
phase: 04-push-recovery-release
plan: 02
subsystem: hub
tags: [apns, alerts, cooldown, hooks]
requires: [04-01]
provides:
  - Sessions onAlert callback (hub: done/waiting/exited; external: Stop/Notification)
  - Push.alert per-session cooldown with trailing collapse (cooldownMs, setTimer options)
affects: [04-03, 04-04]
key-files:
  modified: [hub/sessions.js, hub/apns.js, hub/server.js, hub/hub.test.js]
key-decisions:
  - "Cooldown 10 s per session; identical repeats dropped, a different state in-window is sent once at window end"
  - "s.userStopped set in stop(); 04-03 resume must reset it to false"
requirements-completed: [NOTF-01, NOTF-04]
completed: 2026-11-12
---

# Phase 4 Plan 2: Session alerts Summary

Finished / needs-input / exited sessions now push one terse alert (hub and external, first discovering hook included), with a 10 s per-session cooldown; user stop and hub boot stay silent.

## Commits
- a957ab4 test(04-02): failing tests (RED)
- 0a4336a feat(04-02): session alerts with per-session cooldown (GREEN)

## Verification
`cd hub && node --test hub.test.js` -> `# pass 60` / `# fail 0` (baseline 55 plus 04-01's tests, +5 new here). Live hub not restarted; tests use stub sender.

## Deviations from Plan
- server.js: Push was already constructed before Sessions (from 04-01), so no move was needed.
- Exit code: `onExit` stores `s.exitCode`; alert fires from setState so the code is set before the push.

## Known Stubs
None.

## Self-Check: PASSED
