---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 02
subsystem: app-testing
tags: [xcuitest, snapshot-testing, mock-hub, simulator]
requires: []
provides:
  - hub/tools/mock-hub.mjs (loopback mock of the v1.1 hub contract)
  - app/scripts/test.sh unit|snapshot|ui|all
  - EchoR2AppTests (iOS, SnapshotTesting) and EchoR2UITests targets
  - DEBUG-only launch args -uiTestReset / -uiTestHubHost / -uiTestToken
affects: [05-06, 05-07, 05-08, 05-09, 05-10, 05-11, 05-12]
tech-stack:
  added: [swift-snapshot-testing (from 1.17.0, test target only)]
key-files:
  created:
    - hub/tools/mock-hub.mjs
    - app/scripts/test.sh
    - app/EchoR2UITests/UITestSupport.swift
    - app/EchoR2UITests/SmokeUITests.swift
    - app/EchoR2AppTests/SnapshotSupport.swift
    - app/EchoR2AppTests/SmokeSnapshotTests.swift
    - app/EchoR2AppTests/Fixtures/sessions.json
    - app/EchoR2AppTests/__Snapshots__/SmokeSnapshotTests/testSessionsList.light.png
  modified:
    - app/project.yml
    - app/EchoR2/App/AppModel.swift
    - app/EchoR2/Views/SessionsListView.swift
key-decisions:
  - "Snapshot fixtures omit startedAt so the baseline does not depend on the clock (rows otherwise render 'started N hr. ago')"
  - "Snapshots record with SNAPSHOT_RECORD=1; default mode is .missing"
metrics:
  tasks: 2
  completed: 2026-11-12
---

# Phase 5 Plan 02: Simulator test harness Summary

Mock hub plus iPhone 17 / iOS 26 simulator runner with a snapshot suite and an XCUITest suite, both green.

## Commits

- aadf4fa: mock hub and test.sh
- 0cceee6: test targets, DEBUG launch hooks, smoke UI test, smoke snapshot

## Verification (actual output)

- `sh app/scripts/test.sh snapshot`: `Executed 1 test, with 0 failures` / TEST SUCCEEDED (iOS Simulator)
- `sh app/scripts/test.sh ui`: `testListLoadsFromMockHub passed (7.289 seconds)`, `Executed 1 test, with 0 failures`
- `sh app/scripts/test.sh unit` (macOS EchoR2Tests): `Executed 34 tests, with 0 failures`
- Task 1 curl checks: health has pushLastError, auto-pair returns mock-token, history?limit=3 returns exactly 3 lines, `/sessions` without bearer returns 401.

## Working command

```
xcodebuild test -project EchoR2.xcodeproj -scheme EchoR2 -destination 'platform=iOS Simulator,name=echo-iPhone17' \
  -only-testing:<EchoR2AppTests|EchoR2UITests> -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath "$PWD/build/test-dd" CODE_SIGNING_ALLOWED=NO
```
The simulator device `echo-iPhone17` already existed or was created by test.sh. No other build workaround was needed now that the iOS 26 runtime is installed (SwiftTerm plugin validation skipped via flag; actool worked).

## Deviations from Plan

**1. [Rule 1 - Bug] Clock-dependent snapshot.** The first baseline showed "started 13 hr. ago", which would fail on any later run. Removed `startedAt` from the snapshot fixture and re-recorded. Note for later plans: keep snapshot fixtures free of relative dates.

**2. Record mode.** With `SNAPSHOT_RECORD=1`, SnapshotTesting reports the recording as a test failure by design; the record run exits non-zero. Re-run without the variable to assert.

**3. Mock hub WS.** Only HUB_RUNNING (and EXT_CLI after takeover, since it becomes a hub/running session) accept the stream; stopped/done/external close 4404.

## Known Stubs

None.

## Threat Flags

None. Launch-arg hooks are inside `#if DEBUG`; mock hub binds 127.0.0.1; test.sh only kills `$MOCK_PID`.

## Self-Check: PASSED
Files exist, commits aadf4fa and 0cceee6 exist.
