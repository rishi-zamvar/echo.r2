---
phase: 01-hub-session-engine
plan: 03
subsystem: hub
tags: [write-queue, process-tree-kill, boot-sweep, read-only]
requires: [01-02]
provides:
  - "Per-session serialized write queue; interrupt (Ctrl-C); stop with whole-tree kill; boot PID sweep; external sessions read-only"
  - "cli send | interrupt | stop"
affects: [01-04, 01-05, 01-06]
tech-stack:
  added: []
  patterns: [single promise chain per session, killTree (taskkill /T /F | kill(-pid)), PID-reuse-safe sweep]
key-files:
  created: []
  modified: [hub/sessions.js, hub/server.js, hub/cli.js, hub/hub.test.js]
key-decisions:
  - "input/keys/interrupt are async and reject with code not_found | read_only | not_running; WS maps them to error frames, stop route to 404/409"
  - "Boot sweep kills a stored PID only if alive AND its command/image matches /claude/i; otherwise just marks stopped"
requirements-completed: [SESS-04, SESS-05]
duration: ~15min
completed: 2026-11-11
---

# Phase 1 Plan 03: Steer and Stop Summary

Input from many clients is serialized through one per-session promise chain (paste + `\r` in a single entry), Ctrl-C is deliverable, `stop` kills the whole process tree, externals are read-only, and boot sweeps leftover claude PIDs.

## Tasks

| Task | Commit |
|---|---|
| 1 Failing tests (5 new, RED) | see git log `test(01-03)` |
| 2 Queue, interrupt, stop/killTree, boot sweep (GREEN, 20/20) | see git log `feat(01-03): write queue...` |
| 3 cli send/interrupt/stop + real-claude smoke | see git log `feat(01-03): cli send...` |

## Smoke (real claude 2.1.322, cwd /Users/rishizamvar)
- `interrupt` after 5 s: "Interrupted" text WAS present in /tmp/i.out.
- `send "reply with the single word pong"` returned rc 0; session reached `done`.
- `stop` printed `stopped <id8>`; `/tmp/orphans.out` empty (pgrep for session id found nothing); `/tmp/stop-list.out` shows ` exited `.
- Interrupt and Stop hook (checker warning 5): in a second run, state went `running` -> `done` within about 1 s of the interrupt with no other input, so Ctrl-C does cause the state to leave `running` (consistent with a Stop hook firing on interrupt, or the model finishing; not separately distinguished). Treat `done` after interrupt as normal.
- Hub and all claude processes killed afterward (pgrep clean).

## Deviations from Plan
- Used cwd /Users/rishizamvar for the smoke (echo.r2 triggers the trust dialog), as instructed.
- `cli send` connects with `since=MAX_SAFE_INTEGER&epoch=<current>` so replay is skipped; no plan change otherwise.

## Known Stubs
None.

## Threat Flags
None beyond the plan's model; T-01-13..16 mitigated. Windows tree-kill (taskkill path, `pty.kill()` without signal) is untested on the Mac; verified by PC spike S4 / plan 06.

## Self-Check: PASSED
`node --test hub/hub.test.js` 20/20; hub/cli.js usage lists all six commands.
