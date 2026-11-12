---
phase: 03-ios-app
plan: 04
subsystem: ios-app
tags: [swiftui, chat, navigation, markdown, reconnect]
requires: [03-03]
provides:
  - NavigationStack path in AppModel (rows and new sessions navigate to detail)
  - SessionDetailModel (@MainActor @Observable; owns SessionStream, retains cursor across stop/start)
  - SessionDetailView (toolbar live state chip, Interrupt/Stop menu, scenePhase lifecycle)
  - ChatView (bubbles, inline markdown, tool rows, composer, read-only note, jump-to-latest)
affects: [03-05]
key-files:
  created:
    - app/EchoR2/Views/SessionDetailModel.swift
    - app/EchoR2/Views/SessionDetailView.swift
    - app/EchoR2/Views/ChatView.swift
  modified:
    - app/EchoR2/App/AppModel.swift
    - app/EchoR2/App/EchoR2App.swift
    - app/EchoR2/Views/SessionsListView.swift
key-decisions:
  - "Cursor is retained on the model (not the stream), so background/reopen reconnects with since/epoch and produces no duplicate chat lines"
  - "StateChip extracted from SessionRow and reused in the detail toolbar with the stream's live state"
  - "SessionDetailModel is built in the view init with info nil; adopt(info) in onAppear fills readOnly/state (app.sessions is not reachable from init)"
metrics:
  tasks: 2
  completed: 2026-11-11
---

# Phase 3 Plan 04: Chat Detail Summary

Sessions open into a live chat (user right, assistant markdown left, one-line mono tool rows) with send, Interrupt, confirmed Stop, read-only external sessions, and delta-only resume after background.

## Commits

- 27ec942: navigation path, list NavigationLinks, SessionDetailModel
- 3ba7929: SessionDetailView and ChatView

## Verification

- iOS build (03-01 workaround: -target, iphonesimulator SDK, absolute SYMROOT, Assets.xcassets moved aside then restored): no errors under Swift 6 strict concurrency.
- macOS tests: green (23 tests).
- Acceptance greps: `$app.path` 1, `initialState: cursor` 1, `inlineOnlyPreservingWhitespace`, "Watching", "Stop this session", `scenePhase` present.
- Working tree clean of verification workarounds after build.

## Deviations from Plan

- Tasks were committed in a split that is not independently buildable: Task 1's commit references SessionDetailView/ChatView, which landed in the second commit (same working tree, files interdependent). Final state builds.
- Added `adopt(_:)` and `StateChip` (small helpers not in the plan) to wire app.sessions info into the model and share the chip.
- Build command differs from plan (no simulator runtime), as in 03-01/03-03.

## Known Stubs

None. `.effect(.term)` is intentionally ignored (03-05 feeds the terminal).

## Not verified (deferred to Phase 4 on-device)

Live chat against the hub, background/foreground without duplicate bubbles, auto-scroll and Jump-to-latest behavior, external read-only view, Stop/Interrupt on a real session. No UI was run (no simulator; hub not touched).

## Self-Check: PASSED
Files exist; commits 27ec942, 3ba7929 exist.
