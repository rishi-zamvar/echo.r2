---
phase: 03-ios-app
plan: 02
subsystem: ios-app
tags: [swiftui, polling, sessions-list, new-session]
requires: [03-01]
provides:
  - Sessions list home with 3 s polling, chips, sort, external labeling
  - New Session sheet (roots picker, optional prompt, onCreated closure)
  - SessionInfo.chip / sortRank / sorted (tested)
affects: [03-04]
key-files:
  created:
    - app/EchoR2/Views/SessionsListView.swift
    - app/EchoR2/Views/NewSessionView.swift
  modified:
    - app/EchoR2/Core/Models.swift
    - app/EchoR2/App/AppModel.swift
    - app/EchoR2/App/EchoR2App.swift
    - app/EchoR2Tests/ModelsTests.swift
key-decisions:
  - "Polling lives in the view .task so SwiftUI cancels it on disappear/background"
  - "Chip in the list is a static capsule (DesignSystem Chip is a Button)"
metrics:
  tasks: 2
  completed: 2026-11-11
---

# Phase 3 Plan 02: Sessions List and New Session Summary

Paired home is now a live-polling, sorted, chip-labeled Sessions list under a ConnectionBanner, with a "+" sheet that starts a session in an allowlisted folder.

## Commits

- cfce7dc: New Session sheet (Task 2 file, committed first because it depends only on 03-01 code)
- f1cffd1: Sessions list, chip/sort helpers + tests, AppModel polling, RootView wiring (Task 1)

## Verification

- macOS tests: 9 tests, 0 failures (new testChipAndTitle, testSorted).
- iOS app build: BUILD SUCCEEDED using the 03-01 `-target` / iphonesimulator workaround, with Assets.xcassets moved aside during the build and restored (git status clean afterward).
- Not verified (deferred to Phase 4 on-device): live list, New Session end to end, banner in airplane mode, visuals.

## Deviations from Plan

- Commit order swapped (Task 2 before Task 1) so each commit compiles on its own. TDD RED/GREEN commits were not split; tests and implementation landed together in one commit.
- bootstrap() returns early on a health failure (does not call refreshSessions), and also resets sessions on forget().
- Added `sessionsLoaded` to AppModel to distinguish "loading" from "empty".
- Toasts: `.wcoachToasts()` attached inside the sheet, since sheets are separate presentation contexts. No root-level toast overlay was added.

## Known Stubs

None. NewSessionView's `onCreated` is currently `{ _ in }` in SessionsListView; 03-04 wires it to push the session.

## Self-Check: PASSED
Files exist; commits cfce7dc and f1cffd1 exist.
