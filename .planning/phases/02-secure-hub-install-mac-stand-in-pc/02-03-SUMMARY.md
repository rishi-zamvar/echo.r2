---
phase: 02-secure-hub-install-mac-stand-in-pc
plan: 03
subsystem: hub
tags: [allowlist, roots, ext-hooks, logging]
requires: [02-02]
provides: [inRoots, listRoots, GET /sessions/roots, /hook/ext/<secret>, openLog]
affects: [02-04]
tech-stack:
  added: []
  patterns: [realpath+relative containment, console redirect to rotating file in main block only]
key-files:
  created: []
  modified: [hub/auth.js, hub/hooks.js, hub/server.js, hub/hub.test.js]
decisions:
  - "ext hook drops events for hub-owned ids in onExtHook (server.js), not in hooks.js"
requirements-completed: [HUB-02, HUB-04]
duration: ~10min
completed: 2026-11-11
---

# Phase 2 Plan 03: cwd allowlist, roots picker, ext hooks, rotating log Summary

POST /sessions now requires cwd to realpath inside config.roots (symlink escape and prefix-sibling tested, both listeners), GET /sessions/roots feeds the picker, global-hook sessions report via loopback `/hook/ext/<hookSecret>`, and the hub logs to a 5 MB-rotating hub.log with stdout empty.

## Commits
- ebaa2de: test(02-03): failing tests (RED: suite failed to load, openLog not exported)
- 04de7a9: feat(02-03): implementation (GREEN: 46 pass, 0 fail)

## Smoke
Temp data dir, ports 18790/18791: hub.log has the startup line `echo hub 0.1.0 ebaa2de loopback 127.0.0.1:18790`, stdout 0 bytes, process killed.

## Deviations from Plan
- [Rule 3] Three existing tests (boot marks stopped, stop kills tree, hub session chat) start extra hubs with fresh data dirs whose default roots exclude os.tmpdir(); added an `rdir()` test helper writing config roots. No production change.
- 'sessions roots' test uses a `!roots-` prefixed dir so it sorts inside the 200-entry cap of a crowded tmpdir.
- Console audit: no console call in hub/*.js interpolates tokens, codes, headers or transcript text. No `dangerously-skip-permissions` anywhere.

## Known Stubs
None.

## Self-Check: PASSED
