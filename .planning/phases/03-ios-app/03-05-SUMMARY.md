---
phase: 03-ios-app
plan: 05
subsystem: ios-app
tags: [swiftterm, terminal, trust-detector, swiftui]
requires: [03-04]
provides:
  - TrustDetector (rolling 2048-char ANSI-stripped tail, tested)
  - TerminalScreen (UIViewRepresentable + Coordinator), ExtraKeysBar, TerminalCard
  - Chat | Terminal toggle (persisted per session, disabled for externals)
  - Trust-dialog banner in ChatView
affects: []
key-files:
  created:
    - app/EchoR2/Core/TrustDetector.swift
    - app/EchoR2Tests/TrustDetectorTests.swift
    - app/EchoR2/Views/TerminalScreen.swift
  modified:
    - app/EchoR2/Views/SessionDetailModel.swift
    - app/EchoR2/Views/SessionDetailView.swift
    - app/EchoR2/Views/ChatView.swift
key-decisions:
  - "TerminalView owned by SessionDetailModel (created once) so scrollback survives tab switches"
  - "Last terminal size is tracked from sizeChanged (TerminalView.getTerminal() is internal in SwiftTerm 1.99.1) and re-sent on .live"
  - "Replay term bytes skip trust detection; live batches assign trustPrompt (not OR-ed)"
requirements-completed: [TERM-01, TERM-02, TERM-03]
metrics:
  tasks: 2
  completed: 2026-11-11
---

# Phase 3 Plan 05: Terminal Tab Summary

Sessions flip between Chat and a live SwiftTerm terminal with an extra-keys bar, debounced resize, and a Chat banner when Claude is stuck on the folder-trust dialog.

## Commits

- ecbd20b: TrustDetector + 6 tests
- cfe333a: TerminalScreen, toggle, model wiring, trust banner

## Verification (actual output)

- macOS tests: `Executed 29 tests, with 0 failures (0 unexpected)` / `** TEST SUCCEEDED **`
- iOS build (03-01 workaround: `-target`, iphonesimulator SDK, Assets.xcassets moved aside then restored): `** BUILD SUCCEEDED **`
- Acceptance greps passed (`trustPrompt = trust.feed` 1, `|| trustPrompt` 0). Working tree clean of workarounds.

## Deviations from Plan

1. **[Rule 3] getTerminal() not accessible**: `TerminalView.getTerminal()` is internal in 1.99.1, so the model caches the last size from `sizeChanged` and re-sends it on `.live` instead of reading cols/rows. RIS fallback (`ESC c`) is used for reset.
2. **[Rule 3] Extra delegate methods**: `clipboardRead` (returns nil), `kittyClipboardCapabilities` (empty) and `rangeChanged` are required by the protocol in 1.99.1; implemented as no-ops (denies all remote clipboard access, T-03-19).
3. TDD: implementation and tests written together (a first regex-based version failed Swift 6 concurrency on a static `Regex`; replaced by a manual ANSI scan). No separate RED commit.
4. No captured trust-dialog fixture exists; phrases are from Phase 1 research ("trust this folder") plus "do you trust the files in this folder" from the plan.
5. Arrow keys use `ESC [ A` form (research A6 unverified on device).

## Known Stubs

None.

## Not verified (deferred to Phase 4 on-device)

Claude TUI render fidelity, 5 MB burst, arrow key variant, keyboard/extra-keys layout, trust dialog answered from Terminal, UI never run (no simulator).

## Self-Check: PASSED
Files exist; commits ecbd20b, cfe333a exist.
