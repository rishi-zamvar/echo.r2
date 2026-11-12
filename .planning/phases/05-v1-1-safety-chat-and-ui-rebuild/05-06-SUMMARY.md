---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 06
subsystem: app-chat
tags: [history, continue-here, composer, relay-tolerance, xcuitest]
requires: [05-02, 05-04]
provides:
  - Core/History.swift (HistoryResponse, ChatLine.merge)
  - ChatLine.index (transcript `i`), id keyed by index
  - HubClient.history(id:before:limit:), 15 s request timeout
  - Detail slice: history-first load, Continue here, always-on composer, auto-resume on send
  - AppModel.relayReconnecting() (3 s debounce)
key-files:
  created:
    - app/EchoR2/Core/History.swift
    - app/EchoR2Tests/HistoryTests.swift
    - app/EchoR2UITests/SessionDetailUITests.swift
  modified:
    - app/EchoR2/Core/Frame.swift
    - app/EchoR2/Core/HubClient.swift
    - app/EchoR2/Views/SessionDetailModel.swift
    - app/EchoR2/Views/SessionDetailView.swift
    - app/EchoR2/Views/ChatView.swift
    - app/EchoR2/App/AppModel.swift
    - app/EchoR2Tests/FrameTests.swift
key-decisions:
  - "Stream .resetUI no longer clears chat; index-based merge makes replays idempotent"
  - "4404 sets historyOnly (not notFound) when history loaded; notFound only if history also failed"
  - "Take over menu item and confirmation dialog removed; Continue here is a direct primary button in the header card"
metrics:
  tasks: 3
  completed: 2026-11-12
---

# Phase 5 Plan 06: Chat history, Continue here, send Summary

Every session now opens with its full transcript (paged, deduped by transcript index), externals offer a guarded Continue here, hub sessions always show the composer, and send was proven end-to-end on the live hub.

## Commits

- a008b16: test(05-06): history contract, index-aware ChatLine, merge, failing detail E2E flows (RED)
- e82f87f: feat(05-06): history-first detail, Continue here, always-on composer, relay tolerance (GREEN)
- 8fac2f1: test(05-06): opt-in live-hub send E2E (final form of testLiveHubSend)

## Verification (actual output)

RED (after Task 1, before Task 2): `Executed 5 tests, with 1 test skipped and 4 failures` (testContinueHereRefusedForEvenTerminal, testContinueHereTakesOver, testSendInHubSession, testStoppedSessionShowsHistory all failed); SmokeUITests passed.

After Task 2:
- `sh app/scripts/test.sh ui`: `Executed 6 tests, with 1 test skipped and 0 failures` / TEST SUCCEEDED (the skip is testLiveHubSend)
- `sh app/scripts/test.sh unit`: `Executed 39 tests, with 0 failures` / TEST SUCCEEDED (includes HistoryTests, 4 tests)
- `sh app/scripts/test.sh snapshot`: `Executed 1 test, with 0 failures` / TEST SUCCEEDED

## Live-hub E2E (Task 3)

- Created session `ff93261c` via `node hub/cli.js new /Users/rishizamvar` (trusted cwd, no trust dialog appeared).
- `TEST_RUNNER_LIVE_HUB_SESSION=ff93261c-... xcodebuild test ... -only-testing:EchoR2UITests/SessionDetailUITests/testLiveHubSend`: `testLiveHubSend passed (14.287 seconds)`, `Executed 1 test, with 0 failures`, TEST SUCCEEDED.
- Hub history confirms the round trip: `{i:0,user,"Reply with exactly: echo-e2e-ok"}`, `{i:1,assistant,"echo-e2e-ok"}`.
- Stopped only that session afterwards: `node hub/cli.js list` shows `ff93261c exited`.
- No screenshot was captured: the XCUITest terminates the app on completion and the hub transcript above is the recorded proof instead.
- The test was run once with a looser final assertion, then tightened to an exact-label match on the reply bubble (8fac2f1); the tightened version was not re-run live (the earlier run already matched the exact `echo-e2e-ok` reply per the history above), and the normal ui suite confirms it compiles and skips.

## Deviations from Plan

- **[Rule 3] HubClient.raw query strings:** `appendingPathComponent` percent-encodes `?`, so history paths with `before`/`limit` would break. `raw` now builds the URL from the string when the path contains `?`.
- **[Rule 1] FrameTests:** existing assertion `a.id == 4` updated to `"s4"` for the new String id.
- **Resume return value:** `resume(app:)` now returns Bool so `send` can abort on refusal.
- Old "Stopped / Resume" overlay removed (history + always-on composer supersede it); toolbar Resume menu item kept for stopped/exited sessions.

## Known Stubs

None. Not covered by automation: scroll-to-top older-page loading and the 3 s relay debounce (logic present, unit-tested only via merge); the mock stopped session cannot actually resume (stream 4404), so auto-resume-on-send is exercised only against the live hub path logic.

## Threat Flags

None. App has no force path; hub guards (D-03) are authoritative and refusals are surfaced as text (T-05-20). Live test is env-gated, loopback only, stopped only its own session (T-05-21).

## Self-Check: PASSED
Files exist; commits a008b16, e82f87f, 8fac2f1 exist.
