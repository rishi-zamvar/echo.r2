---
phase: 01-hub-session-engine
plan: 04
subsystem: hub
tags: [transcript, tailer, external-discovery, chat-events]
requires: [01-03]
provides:
  - "hub/transcript.js: parseLine, Tailer, findTranscript, labelFor, discoverExternal, liveSessionIds"
  - "chat events for hub and external sessions; read-only external sessions with label/title; cli chat attach"
affects: [01-05, 01-06]
tech-stack:
  added: []
  patterns: [byte-offset tailer with Buffer remainder, 5 s discovery scan, no persistence of externals]
key-files:
  created: [hub/transcript.js]
  modified: [hub/sessions.js, hub/server.js, hub/cli.js, hub/hub.test.js]
key-decisions:
  - "Externals are never persisted; discovery rebuilds them each boot and a scan prunes discovery-created ones that age out"
  - "Hook-created externals only tail via findTranscript(id), never the hook-supplied transcript_path (T-01-22)"
requirements-completed: [SESS-02, SESS-05]
duration: ~20min
completed: 2026-11-11
---

# Phase 1 Plan 04: Transcripts and External Discovery Summary

Transcripts become chat events (user text, assistant text, one-line tool summaries) for hub and external sessions; Claude sessions started outside the hub are discovered under `<claudeHome>/projects` and listed as read-only `external` with source label and title.

## Commits
| Task | Commit |
|---|---|
| 1 Failing tests (RED) | 6279c7f |
| 2 transcript.js + wiring (GREEN, 26/26) | 67297d0 |
| 3 cli chat attach for externals | 4d2d8c3 |

## Smoke (Mac, real transcripts)
- Hub scan listed 7 externals, labels observed: `Terminal`, `Even Terminal/SDK`, `claude -p`, each with a title. State and source `external`.
- `attach <id8> --for 3` on a real "pong" session printed `you: ...` and `claude: pong` (chat view, no raw mode, no input forwarded). Outputs in /tmp/ext-list.out and /tmp/ext-chat.out.
- Hub process killed; pgrep clean. No external session received input.

## Deviations from Plan
- Fresh `claude -p` via `env -i` reported "Not logged in" (the scrubbed env loses the auth), so the smoke used already-existing real external transcripts (including earlier plan-03 smoke runs) instead of a newly created one. The path exercised is identical.
- [Rule 1] `list()` previously re-listed persisted prior externals forever; it now excludes `source: external` from prior and persistence.
- Test indexes into the fixture were corrected within the GREEN commit.

## Known Stubs
None.

## Threat Flags
None beyond the plan model (T-01-18..22 mitigated: ring cap, 64 KB edge reads, per-line try/catch, type whitelist, UUID-only basenames, read_only guard asserted by test).

## Self-Check: PASSED
`node --test hub/hub.test.js` 26/26; commits 6279c7f, 67297d0, 4d2d8c3 present; `ls hub/*.js` = 8.
