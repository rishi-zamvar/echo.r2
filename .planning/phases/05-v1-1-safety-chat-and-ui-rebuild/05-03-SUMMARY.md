---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 03
subsystem: hub
tags: [safety, even-terminal, alerts, installer]
requires: [05-01]
provides: [global-hooks opt-in, transcript-derived external alerts, D-03 takeover/resume guards]
affects: [hub/sessions.js, hub/transcript.js, hub/server.js, hub/install/install.sh]
key-files:
  modified: [hub/install/install.sh, hub/install/install.ps1, hub/RUNBOOK.md, hub/transcript.js, hub/sessions.js, hub/server.js, hub/hub.test.js, hub/tools/safety-harness.mjs]
decisions:
  - "Guards fail closed: ps scan error or win32 = live_elsewhere"
  - "D-03 guard runs before not_resumable/busy for externals, so resume of an sdk-ts external reports even_terminal"
metrics:
  tasks: 3
  completed: 2026-11-12
---

# Phase 5 Plan 03: Hands-off Even Terminal Summary

Installer no longer touches `~/.claude/settings.json` unless `--global-hooks` (`-GlobalHooks` on PC) is given; external done/waiting alerts come from the transcript tail; takeover/resume of sdk-ts (Even Terminal) or any live-referenced session is refused with 409.

## Commits
- 45dc51d: feat(05-03): global Claude hooks opt-in via --global-hooks
- 11299cc: feat(05-03): transcript-derived external alerts and D-03 takeover/resume guards (tasks 2 and 3 share files, one commit)

## Verification
- `cd hub && node --test hub.test.js`: `# pass 71`, `# fail 0` (66 baseline + 5 new tests)
- `node hub/tools/safety-harness.mjs 50`: `safety ok 50 restarts, 0 external kills`, with takeover and resume of the sdk-ts ET_ID returning 409 even_terminal every iteration
- `install.sh --dry-run` prints `global hooks: off`; with `--global-hooks` prints `on`. `~/.claude/settings.json` mtime unchanged (Nov 12 00:18) before and after.
- Deployed with `sh hub/install/deploy.sh`: live `/health` gitSha `11299cc` equals HEAD.

## Deviations from Plan
- The plan listed 4 alert tests; delivered 2 alert tests (catch-up + end_turn once; tool_use stall waiting once) plus a discovery-entrypoint test, a guards test (sdk-ts, live ps reference, hub's own child not counted), and a stopped-hub-session sdk-ts resume test. The stall-reset check is weak (asserts at most one extra alert).
- Dry-run prints the `global hooks:` line after the plist, so the plist lint test strips it first.
- External `resume` now reports even_terminal/live_elsewhere ahead of not_resumable (needed for the harness assertion).
- Deploy was `git pull` no-op plus `npm ci` and launchd kickstart; checkout is the live hub's working dir.

## Known Stubs
None.

## Self-Check: PASSED
