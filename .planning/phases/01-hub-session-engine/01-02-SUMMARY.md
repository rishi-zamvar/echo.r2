---
phase: 01-hub-session-engine
plan: 02
subsystem: hub
tags: [hooks, state-machine, http-hook, debounce]
requires: [01-01]
provides:
  - "Live session state (starting/running/waiting/done/exited/stopped/external) via one pure transition()"
  - "Loopback hook listener 127.0.0.1:8791 with per-boot secret; per-process --settings hub-hooks.json"
affects: [01-03, 01-04]
tech-stack:
  added: []
  patterns: [pure transition table, answer-then-parse hook receiver, per-process --settings hooks]
key-files:
  created: [hub/hooks.js]
  modified: [hub/sessions.js, hub/server.js, hub/cli.js, hub/hub.test.js]
key-decisions:
  - "hub-hooks.json uses Claude's matcher-group nesting ({Stop:[{hooks:[{type:'http',...}]}]}); verified end to end with real claude"
  - "Externals only created for UUID-shaped session ids; unknown hooks never mutate hub sessions"
requirements-completed: [SESS-02]
duration: ~15min
completed: 2026-11-11
---

# Phase 1 Plan 02: Live Session State Summary

Real Claude `Stop`/`Notification` http hooks (injected per process with `--settings`) hit a secret-protected loopback listener and drive a single pure `transition()` function; `cli list` shows the state.

## Tasks

| Task | Commit |
|---|---|
| 1 Failing tests (RED, 9 new tests) | b656454 |
| 2 hooks.js, transition(), debounce, boot marking, wiring (GREEN, 15/15) | f3b4567 |
| 3 cli state output + real-claude smoke | 96e09e8 |

## Smoke
Real claude (cwd /Users/rishizamvar, prompt "reply with the single word pong"): `cli list` showed `00debf9a done hub /Users/rishizamvar` within 60 s, so the http hook with `$ECHO_SECRET` header interpolation works through `--settings`. Output saved to /tmp/list.out. Hub and claude processes killed afterward.

## Deviations from Plan
- **[Rule 1] hooks file shape:** interface listed bare `{type:'http'}` entries; Claude's schema nests them in `{hooks:[...]}` matcher groups, so the file uses that. Smoke confirms it fires.
- Added `label` to list() output so external rows show `Unknown`.
- Unknown-id external records require a UUID-shaped id (extra input validation, T-01-10).

## Known Stubs
None. External records have no transcript/label yet by design (plan 04).

## Threat Flags
None beyond the plan's threat model (T-01-08..12 mitigated: timingSafeEqual 403, 1 MB cap, 200-before-parse, secret not logged or written to disk, bind 127.0.0.1).

## Self-Check: PASSED
hub/hooks.js exists; commits b656454, f3b4567, 96e09e8 exist; `node --test hub/hub.test.js` 15/15.
