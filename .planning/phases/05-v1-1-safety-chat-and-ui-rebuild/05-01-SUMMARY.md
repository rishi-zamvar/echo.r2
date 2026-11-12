---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 01
subsystem: hub
tags: [safety, kill-paths, even-terminal]
requires: []
provides: [guarded hub kill paths, safety-harness]
affects: [hub/sessions.js]
key-files:
  created: [hub/tools/safety-harness.mjs]
  modified: [hub/sessions.js, hub/hub.test.js]
decisions:
  - "Fail closed: any ps error in parentIsEvenTerminal means do not kill"
metrics:
  tasks: 2
  completed: 2026-11-12
---

# Phase 5 Plan 01: Safety kill guards Summary

Hub can only kill pids it spawned this boot (`#spawned` + `#killOwned`), and the boot sweep additionally requires the exact session id on the command line and a non-Even-Terminal parent.

## Commits
- 62ee3d1: feat(05-01): guard hub kill paths
- becfff2: feat(05-01): add isolated P0-1 safety harness

## Verification
- `cd hub && node --test hub.test.js`: `# pass 66`, `# fail 0` (was 64; +2 new tests)
- `node hub/tools/safety-harness.mjs 50`: `safety ok 50 restarts, 0 external kills`
- Negative proof: with `&& !parentIsEvenTerminal(p.pid)` temporarily removed, harness printed `safety FAIL 1 external kills` (exit 1). Guard restored; not committed.
- Kill log lines are `kill pid <pid> <id8> <reason>` / `kill refused pid <pid> <id8>`; never the command line.

## Deviations from Plan
None. Note: the harness starts hubs with default tailscale config, so each iteration also opens a tailnet listener on port 0 (harmless, closed on `close()`). The live check with real Even Terminal remains Rishi's step in 05-12.

## Self-Check: PASSED
