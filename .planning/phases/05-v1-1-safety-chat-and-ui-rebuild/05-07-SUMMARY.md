---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 07
subsystem: app-list-pairing
tags: [auto-pair, session-list, push-errors, xcuitest]
requires: [05-05, 05-06]
provides:
  - SessionInfo summary/noise/lastActivity/entrypoint, Activity tone, D-08 sort
  - Health.pushLastError, PushResult.message, HubClient.pairAuto, PairingCode.normalize
  - Zero-tap auto-pair with code fallback; plain-language push errors in Settings
  - Session list: summary line, collapsed Other section, active vs inactive tones
key-files:
  modified:
    - app/EchoR2/Core/Models.swift
    - app/EchoR2/Core/HubClient.swift
    - app/EchoR2/App/AppModel.swift
    - app/EchoR2/Views/PairingView.swift
    - app/EchoR2/Views/SettingsView.swift
    - app/EchoR2/Views/SessionsListView.swift
    - app/EchoR2Tests/ModelsTests.swift
    - app/EchoR2UITests/ListPairingUITests.swift
    - app/EchoR2AppTests/__Snapshots__/SmokeSnapshotTests/testSessionsList.light.png
requirements-completed: [V11-04, V11-07, V11-08]
completed: 2026-11-12
---

# Phase 5 Plan 07: List, auto-pair, push errors Summary

Summarized, noise-free, activity-sorted session list; zero-tap pairing with code fallback; hub push errors shown in plain words.

## Commits

- e53d362 test(05-07): flows (RED), model, pairAuto, PairingCode
- 90cb176 feat(05-07): auto-pair, code normalisation, push errors in Settings
- 1799e6b docs(05-05): add plan summary (previously untracked)
- 83c0138 feat(05-07): list summary line, collapsed Other, active-first sort, tones (+ re-recorded sessions-list snapshot)

## Test results (final run)

- unit (macOS): `Executed 41 tests, with 0 failures (0 unexpected)` ** TEST SUCCEEDED **
- ui: `Executed 10 tests, with 1 test skipped and 0 failures (0 unexpected)` ** TEST SUCCEEDED ** (skipped = opt-in live-hub E2E from 05-06)
- snapshot: ** TEST SUCCEEDED ** after re-recording

## Deviations

**[Rule 3 - Blocking] Snapshot re-record.** `SmokeSnapshotTests.testSessionsList` failed ("light does not match reference") because the row layout intentionally changed (summary line, activity tones, relative time). Re-recorded with `SNAPSHOT_RECORD=1` (the record run itself exits 1 by design), then verified green on a normal run. Commit 83c0138.

No other deviations. The RED run for Task 1 was captured in e53d362 by the prior interrupted run; its output was not preserved.

## Known Stubs

None.

## Self-Check: PASSED
