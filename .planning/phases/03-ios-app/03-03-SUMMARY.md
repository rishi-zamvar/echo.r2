---
phase: 03-ios-app
plan: 03
subsystem: ios-app
tags: [websocket, replay, dedupe, reconnect, tdd]
requires: [03-02]
provides:
  - Frame decode (never throws) and ClientFrame encode
  - Pure Replay reducer (StreamState, Effect, apply) with seq dedupe and reset-before-replay
  - SessionStream actor (auth WS, seeded cursor, ping timeout, backoff, NWPathMonitor, close codes)
affects: [03-04, 03-05]
key-files:
  created:
    - app/EchoR2/Core/Frame.swift
    - app/EchoR2/Core/Replay.swift
    - app/EchoR2/Net/SessionStream.swift
    - app/EchoR2Tests/FrameTests.swift
    - app/EchoR2Tests/ReplayTests.swift
key-decisions:
  - "Token only in Authorization header; query carries since/epoch only"
  - "Network change while live cancels the socket and skips backoff; while reconnecting it cancels the backoff sleep"
  - "Ping timeout cancels the socket (which also unblocks the pending ping continuation)"
metrics:
  tasks: 2
  completed: 2026-11-11
---

# Phase 3 Plan 03: Live Session Stream Summary

Decoding, dedupe/replay and a self-healing authenticated WebSocket actor; reconnect without duplicates (CONN-01) is proven at the reducer level.

## Commits

- 892e030: test(03-03) failing Frame/Replay tests (RED; build failed on missing types)
- bc802e0: feat(03-03) Frame decoding and Replay reducer (GREEN)
- b03b1e8: feat(03-03) SessionStream actor

## Verification

- macOS tests: 23 tests, 0 failures (5 Frame, 7 Replay including testReconnectSeededCursorAppliesOnlyNewEvents).
- iOS build: BUILD SUCCEEDED under Swift 6 strict concurrency using the 03-01 workaround (-target, iphonesimulator SDK, absolute SYMROOT, Assets.xcassets moved aside then restored; git status clean).
- Acceptance greps all pass (single Authorization header line, no logging, 4404/4401, NWPathMonitor, sendPing, `.cursor(`).
- Not verified (deferred to Phase 4 on-device): airplane-mode recovery, Wi-Fi/cellular switch, Authorization header honored on upgrade over tailnet (A7), ping timeout path. SessionStream has no unit tests (needs a live socket; the hub was not touched).

## Deviations from Plan

- Build command: SYMROOT must be absolute (relative path resolved inside the SwiftTerm checkout). Otherwise as in 03-01.
- StreamStatus is the top-level name for the plan's `Status` enum (avoids a nested-type name clash in consumers).
- STATE.md plan counter was wrong (7/7); set to phase 3, plan 4 of 5 per orchestrator note.

## Known Stubs

None.

## Notes for 03-04

- Consumers read `outputs`; keep the last `.cursor(state)` and pass it as `initialState` for a new stream on foreground.
- `.status(.unauthorized)` should route to AppModel.handle (wipe token); `.gone` means session 404.

## Self-Check: PASSED
Files exist; commits 892e030, bc802e0, b03b1e8 exist.
