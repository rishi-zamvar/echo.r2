---
phase: 02-secure-hub-install-mac-stand-in-pc
plan: 04
subsystem: hub-install
tags: [launchd, hooks-merge, deploy, runbook]
requires: [02-03]
provides: [hub/install/hooks-merge.js, install.sh, uninstall.sh, deploy.sh, hub/RUNBOOK.md]
affects: [02-05, 02-06]
tech-stack:
  added: []
  patterns: [pure merge/unmerge with marker url, plist via heredoc + plutil -lint, deploy proves gitSha via /health]
key-files:
  created: [hub/install/hooks-merge.js, hub/install/install.sh, hub/install/uninstall.sh, hub/install/deploy.sh, hub/RUNBOOK.md]
  modified: [hub/hub.test.js]
decisions:
  - "hooks-merge CLI unmerge on a missing settings.json is a no-op (no file created)"
requirements-completed: [HUB-01, HUB-04]
duration: ~10min
completed: 2026-11-11
---

# Phase 2 Plan 04: Mac install, deploy, hooks merge, runbook Summary

One-command launchd install (plist with RunAtLoad/KeepAlive/ThrottleInterval 10, absolute node, PATH incl. claude dir) plus non-destructive Stop/Notification http-hook merge into settings.json, a deploy script that prints `deployed <sha>` only when /health shows the new gitSha, and an operator runbook. Not installed live (that is 02-06).

## Commits
- 0bb7bbb: test(02-04): failing hooks-merge and plist tests (RED: 3 fail, 46 pass)
- 1895eed: feat(02-04): install/uninstall/deploy and settings hook merge (GREEN: 49 pass, 0 fail)
- e4ea8d2: docs(02-04): hub runbook

## Verification
`sh -n` clean on all scripts, `install.sh --dry-run | plutil -lint -` OK, forbidden-word grep empty, no LaunchAgent plist created, real ~/.claude untouched (tests use temp paths).

## Deviations from Plan
- [Rule 1] Test file already declared `posix` (a skip-option object); removed my duplicate and used `posix.skip`. Test-only.

## Known Stubs
None.

## Self-Check: PASSED
