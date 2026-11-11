---
phase: 01-hub-session-engine
plan: 01
subsystem: hub
tags: [node-pty, ws, eventlog, replay, cli]
requires: []
provides:
  - "hub/ walking skeleton: REST + WS stream with seq/epoch replay, PTY-hosted claude, CLI"
affects: [01-02, 01-03, 01-04]
tech-stack:
  added: [node-pty@1.1.0, ws@8.22.2]
  patterns: [coalesced base64 term events, single seq ring, atomic JSON store]
key-files:
  created:
    - hub/package.json
    - hub/package-lock.json
    - hub/server.js
    - hub/sessions.js
    - hub/eventlog.js
    - hub/store.js
    - hub/cli.js
    - hub/hub.test.js
    - hub/fixtures/fake-claude.mjs
    - hub/fixtures/transcript-sample.jsonl
key-decisions:
  - "spawn-helper chmod done in Sessions constructor (no postinstall script needed)"
  - "Task 1 package-legitimacy gate approved by user for node-pty@1.1.0 and ws@8.22.2 before npm i"
requirements-completed: [SESS-03]
duration: ~20min
completed: 2026-11-11
---

# Phase 1 Plan 01: Hub Walking Skeleton Summary

Real `claude --session-id <uuid>` hosted in a node-pty PTY inside a loopback-only hub, with a seq-numbered EventLog and `since`/`epoch` WS replay, driven by a `list|new|attach` CLI.

## Tasks

| Task | Commit |
|---|---|
| 1 Package legitimacy gate (user approved node-pty@1.1.0, ws@8.22.2) | n/a |
| 2 Scaffold + failing tests (RED) | 6454b37 |
| 3 Hub slice (GREEN, 6/6 tests) | 37de2a1 |
| 4 CLI + Mac smoke | 73d2064 |

## Mac smoke results
- Open Question 1 / A8: the positional prompt **was submitted automatically: yes**. Claude answered `42` and `42` appears in /tmp/a1.out.
- Re-attach with `--since <seq>` printed `detached seq=26 ...`; the session was idle so the replay was empty (0 bytes), as expected. `list` showed the 8-char id, `running`.
- Pitfall 3 confirmed: the first attempt in /Users/rishizamvar/Documents/Projects/echo.r2 hit the "trust this folder" dialog (that cwd is not trusted in ~/.claude.json), so the smoke was rerun with cwd `/Users/rishizamvar` (already trusted). No Claude config was modified. Phase 3 allowlist must only contain pre-trusted dirs.
- Hub and claude processes were killed afterwards (none left).

## Deviations from Plan
- **[Rule 3] Smoke cwd** changed to a trusted directory (above); not a code change.
- No postinstall script added: Sessions constructor already chmods the darwin spawn-helper.
- Added `Sessions.killAll()` (used by `killOnClose` in tests) and a `server` field on the startHub return (tests need the address).

## Known Stubs
None. `Sessions.prior` (records from a previous boot) is listed unchanged by design; plan 02 marks them stopped.

## Threat Flags
None beyond the plan's threat model.

## Self-Check: PASSED
All files and commits (6454b37, 37de2a1, 73d2064) exist; `node --test hub/hub.test.js` 6/6 pass.
