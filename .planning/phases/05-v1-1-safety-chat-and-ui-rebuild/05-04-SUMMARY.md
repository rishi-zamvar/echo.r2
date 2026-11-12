---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 04
subsystem: hub
tags: [history, chat, summary, noise]
requires: [05-03]
provides: [GET /sessions/:id/history, indexed chat events, summary/noise/lastActivity/entrypoint on /sessions, 7-day dormant externals]
affects: [hub/transcript.js, hub/sessions.js, hub/server.js, hub/hub.test.js]
key-files:
  modified: [hub/transcript.js, hub/sessions.js, hub/server.js, hub/hub.test.js]
decisions:
  - "list() enriches per call; #persist uses a lean #base() so persistence never reads transcripts"
  - "readHistory is a whole-file read capped at 64 MB (413); history route never logs content"
metrics:
  tasks: 2
  completed: 2026-11-12
---

# Phase 5 Plan 04: Hub history, summary and noise Summary

History endpoint for any session with a transcript (paged by before/limit, works after restart), live chat events carry index `i` matching history, `/sessions` items carry summary/noise/lastActivity/entrypoint, and externals active in the last 7 days are listed (only those active within 30 min or live get a tailer). Deployed.

## Commits
- a13b2b7: feat(05-04): history endpoint, indexed chat events, summary/noise/lastActivity, 7-day dormant externals (both tasks touch the same files, one commit; an earlier hash d2ca716 was amended after a test-count fix)

## Verification
- `cd hub && node --test hub.test.js`: `# pass 77`, `# fail 0` (71 baseline + 6 new)
- `node hub/tools/safety-harness.mjs 50`: `safety ok 50 restarts, 0 external kills`
- `sh hub/install/deploy.sh`: `deployed a13b2b7`; live `/health` gitSha `a13b2b7`; loopback `/sessions` returns summary, noise, lastActivity on all 46 items.

## Deviations from Plan
- Single commit for both tasks (shared files, written together).
- Existing `discovery` test updated: the 2 h old transcript is now listed (inactive) under the 7-day window.
- `Sessions.list()` no longer feeds `#persist`; a private `#base()` does, to avoid transcript reads on every state change.
- noise rule: `userTurns` is exact only for files <= 128 KB (edge-based approximation above, ponytail-commented).

## Known Stubs
None.

## Self-Check: PASSED
