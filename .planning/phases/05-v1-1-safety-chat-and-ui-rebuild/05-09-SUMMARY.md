---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 09
subsystem: app-ui
tags: [chat, terminal, motion, haptics, accessibility, impeccable, swiftui-pro]
requires: [05-08]
provides:
  - ChatGroup/ChatItem (pure grouping of ChatLine into bubbles + "Used N tools" groups, unit-tested)
  - Rebuilt ChatView (bubbles, inline markdown, code insets, tool groups, working indicator, jump pill, designed loading/empty/error)
  - Light paper/ink terminal by default; @AppStorage("terminalDark") warm-ink opt-in, recoloured in place
  - Detail header (summary/folder + state pill + LiveDot, rose flash on waiting), capsule Chat/Terminal toggle with matchedGeometryEffect
  - Session actions menu (Interrupt / Stop confirm / Resume / Dark terminal) with semantic haptics
  - LiveDot component (shared with list row)
affects: [05-10]
key-files:
  created:
    - app/EchoR2/Core/ChatGroup.swift
    - app/EchoR2Tests/ChatGroupTests.swift
  modified:
    - app/EchoR2/Views/ChatView.swift
    - app/EchoR2/Views/SessionDetailView.swift
    - app/EchoR2/Views/SessionDetailModel.swift
    - app/EchoR2/Views/TerminalScreen.swift
    - app/EchoR2/Views/SessionsListView.swift (LiveDot reuse)
    - app/EchoR2/DesignSystem/Components.swift (LiveDot)
key-decisions:
  - "Jump-to-latest uses onScrollGeometryChange(for: Bool) instead of a bottom sentinel's onAppear/onDisappear, which flip-flopped with the keyboard up and hung the UI tests"
  - "Dark terminal = Palette.ink (warm), never black; theme applied via TerminalView.nativeBackground/ForegroundColor on the existing instance so scrollback survives"
  - "Caret colour left at SwiftTerm default (follows foreground), so it flips with the theme for free"
  - "Title stays in the nav bar; header row carries summary (or cwd) + state pill rather than repeating the title"
  - "Dark terminal toggle lives in the Session actions menu, shown only on the Terminal tab"
requirements-completed: [V11-09, V11-10, V11-11]
metrics:
  tasks: 3
  completed: 2026-11-12
---

# Phase 5 Plan 09: UI rebuild part 2 (session detail) Summary

Session detail rebuilt to DESIGN.md: chat reads as a conversation (bubbles, markdown, tools tucked into "Used N tools"), a live Working indicator and jump-to-latest pill, a light paper terminal with an opt-in warm-ink dark theme, an animated capsule Chat/Terminal switch, and haptics on send/arrival/state change/toggles.

## Commits

- d9ddaa4 test(05-09): add failing ChatGroup grouping tests
- 3b7e46d feat(05-09): rebuilt chat - bubbles, markdown, tool groups, working indicator, jump pill
- 63766cd feat(05-09): light terminal default, dark toggle, header, animated Chat/Terminal toggle
- 0e73674 fix(05-09): audit pass - keycaps float on atmosphere; final detail screenshots

## What changed (Task 2)

- Terminal: `nativeBackgroundColor = UIColor(Palette.paper)`, foreground ink, sage selection. `applyTerminalTheme(dark:)` recolours only on change (SwiftTerm's setter forces a full redraw). `TerminalScreen` reads `@AppStorage("terminalDark")` in make/updateUIView.
- Detail screen gets `screenBackground()` (it was system white before) and a header row: summary or cwd, LiveDot when running, StateChip; the pill gets a brief rose wash when the state turns `waiting`. `Haptics.stateChange()` fires on stream state changes (not on the initial unknown to state adopt).
- Chat/Terminal: paper capsule on a sage track that moves with `matchedGeometryEffect`, `Haptics.toggle()`, content slides/fades (opacity only under Reduce Motion). Hidden for read-only externals, not just disabled.
- Actions: Interrupt (toggle haptic), Stop (destructive haptic on open + confirm with a message), Resume (send haptic), Dark terminal toggle.
- Extra keys: paper keycaps (44pt, shadowed), VoiceOver labels "Escape", "Control C", "Up arrow"...

## impeccable critique / audit (Task 3)

Verdict: passes DESIGN.md. Screens checked at default and XXL.
- PASS: no black surfaces by default (terminal-light); dark terminal is warm ink inside a paper card.
- PASS: hierarchy is clear: nav title, summary + pill, toggle, then content. XXL wraps without truncation (header summary takes 2 lines).
- PASS: tool group collapsed by default, expanded block is mono on paper; working pill is calm.
- FIXED: the key-bar's surfaceAlt band stopped above the home indicator (the content `.clipped()` cut its safe-area extension), leaving a lavender strip. The band is gone; keycaps now float on the atmosphere.
- NOTED (not fixed): the watching card repeats "Watching" next to the "watching" pill. It's mild and both read correctly, so I left it.
- NOTED: the mock hub sends no PTY bytes, so the screenshots can't show how ANSI colours look on paper. Needs a look on the real hub.

## swiftui-pro review

- Feedback loops: none of the new state writes (flash, tab, terminalDark) feeds back into its own trigger. `updateUIView` is idempotent through the `themedDark` guard.
- `matchedGeometryEffect` sits in a conditional background inside one namespace, which is the canonical pattern.
- `flashPill` uses an uncancelled Task. Worst case on rapid waiting flips is an early fade. Accepted.
- Identifiers kept: detail.watchingHeader, detail.continueHere, detail.composer, detail.send, detail.working, detail.jumpLatest, detail.tab.chat, detail.tab.terminal, detail.history.empty, detail.error (plus new detail.header, detail.toolGroup).

## Screenshots

`.planning/phases/05-v1-1-safety-chat-and-ui-rebuild/screens/05-09/`: 16 files (chat-running, chat-tools-expanded, terminal-light, terminal-dark, history-stopped, watching-even, continue-refused, continue-cli, each at default and `-xxl`). The `before/` subfolder holds the pre-rebuild captures.

## Verification

- `sh app/scripts/test.sh unit`: 44 tests, 0 failures
- `sh app/scripts/test.sh ui`: 13 tests (3 opt-in screenshot tests skipped), 0 failures

## Deviations from Plan

1. [Rule 1 - Bug, Task 1] I replaced the bottom-sentinel onAppear/onDisappear with onScrollGeometryChange. The sentinel caused a render loop when the keyboard was up, which showed up as UI test hangs.
2. The plan put the "Dark terminal" toggle in a TerminalScreen toolbar menu. It's in the existing Session actions menu instead, shown only on the Terminal tab, which is where the screenshot test already looks for it.
3. The title stays in the system nav bar instead of being repeated in a custom header.

## Known Stubs

None.

## Self-Check: PASSED
