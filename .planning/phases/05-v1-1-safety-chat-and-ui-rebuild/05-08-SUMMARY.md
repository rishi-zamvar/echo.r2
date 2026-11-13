---
phase: 05-v1-1-safety-chat-and-ui-rebuild
plan: 08
subsystem: app-ui
tags: [design-system, impeccable, swiftui-pro, motion, haptics, accessibility, dynamic-type]
requires: [05-07]
provides:
  - app/DESIGN.md (colour roles, no-black rule, type, anatomy, motion map, haptic map, states, a11y)
  - Motion tokens (snappy/list/gentle/breathe/fade) + .motion(_:value:) / Motion.animate honouring Reduce Motion
  - Semantic Haptics (send, arrival, stateChange, refresh, toggle, destructive, failure, paired)
  - Palette state roles (running, needsYou, idle), AA text colours; Typography on Dynamic Type styles
  - Components: screenBackground(), PressableStyle, GroupTitle, LabeledRow, EmptyState(action), SkeletonRow
  - Rebuilt List, Pairing, Settings, New Session; light-only app; serif nav titles
  - Opt-in ScreenshotUITests (TEST_RUNNER_SCREENSHOT_DIR, TEST_RUNNER_SCREENSHOT_XXL)
affects: [05-09, 05-10]
key-files:
  created:
    - app/DESIGN.md
    - app/EchoR2UITests/ScreenshotUITests.swift
  modified:
    - app/project.yml
    - app/EchoR2/App/EchoR2App.swift
    - app/EchoR2/DesignSystem/Palette.swift
    - app/EchoR2/DesignSystem/Animations.swift
    - app/EchoR2/DesignSystem/Haptics.swift
    - app/EchoR2/DesignSystem/Typography.swift
    - app/EchoR2/DesignSystem/Components.swift
    - app/EchoR2/DesignSystem/ConnectionBanner.swift
    - app/EchoR2/DesignSystem/Toast.swift
    - app/EchoR2/Views/SessionsListView.swift
    - app/EchoR2/Views/PairingView.swift
    - app/EchoR2/Views/SettingsView.swift
    - app/EchoR2/Views/NewSessionView.swift
    - app/EchoR2/Views/SessionDetailModel.swift (haptic renames only)
    - app/EchoR2/App/AppModel.swift (haptic rename only)
    - hub/tools/mock-hub.mjs (GET /sessions/roots fixture)
    - app/EchoR2AppTests/__Snapshots__/SmokeSnapshotTests/testSessionsList.light.png
key-decisions:
  - "Root cause of 'black background': no colour-scheme pin, so in dark mode the NavigationStack, Form and sheets painted system black over the atmosphere. Fixed with UIUserInterfaceStyle=Light plus screenBackground() inside the stack"
  - "Stopped/done/watching sessions are idle grey, not danger/rose: only running (sage) and needs-you (rose) carry colour"
  - "Buttons no longer fire haptics themselves; callers fire the semantic haptic for the outcome (paired/failure/send)"
  - "Serif nav titles via one UINavigationBarAppearance hook (SwiftUI has no title-font API)"
requirements-completed: [V11-09, V11-10, V11-11]
metrics:
  tasks: 3
  completed: 2026-11-12
---

# Phase 5 Plan 08: UI rebuild part 1 Summary

List, Pairing, Settings and New Session rebuilt on a written apothecary design direction (app/DESIGN.md). The app is now light-only, with no black surfaces even when the phone is in dark mode, spring motion that respects Reduce Motion, one semantic haptics API, AA contrast, and layouts that hold at XXL Dynamic Type.

## Commits

- 15ad2c7 feat(05-08): design direction (DESIGN.md) and Motion/Haptics/Palette/Type tokens
- 3445cad feat(05-08): rebuild list, pairing, settings, new session on the token system
- 5e4e3df fix(05-08): audit pass: plain status values, push error context, hints; final screenshots

## impeccable critique (before), Task 1

`⚠️ DEGRADED: single-context (no sub-agent tool exposed in this executor; detect.mjs targets web markup, not SwiftUI)`. Mode: Operate. Before screenshots were taken with the simulator in dark appearance, which matches Rishi's phone.

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of status | 2 | State chips all pastel; running vs watching vs stopped hard to tell apart |
| 2 | Match real world | 3 | "(this folder)", "Backend quiet" jargon |
| 3 | User control | 3 | Forget hub looks like any other button |
| 4 | Consistency | 1 | Pairing is lavender, but List, Settings and New Session are system black. Two apps in one |
| 5 | Error prevention | 3 | |
| 6 | Recognition | 3 | |
| 7 | Flexibility | 2 | No Dynamic Type: every font was a fixed point size |
| 8 | Aesthetic/minimal | 1 | Black canvas plus cream cards plus tracked-uppercase eyebrows; repeated AppMark in Settings |
| 9 | Error recovery | 2 | Error text in danger pink at 2.5:1; raw iOS error strings |
| 10 | Help | 3 | |
| **Total** | | **23/40** | Acceptable, with significant work needed |

Top findings:
1. **P0 black surfaces**: NavigationStack/Form/sheet backgrounds go black in dark mode. Pairing text fields render white ink on cream paper, so the host and code you type are invisible.
2. **P1 contrast**: textMuted 2.9:1, danger 2.5:1, accentDeep 3.1:1 and the primary button label 4.3:1 all fail AA.
3. **P1 Dynamic Type**: Typography used `Font.system(size:)`, so nothing scaled.
4. **P2 hierarchy**: eyebrow kickers on every card, AppMark repeated on Settings, all-mono values, idle states coloured like alerts.
5. **P2 motion**: DragGesture press tracking on buttons (fights scrolling), `.spring` literals in views, no Reduce Motion path for list changes.

swiftui-pro review (before): fixed-size fonts (Dynamic Type); `DragGesture(minimumDistance: 0)` press tracking should be a `ButtonStyle`; unlabeled icon-only `plus` had a label but no identifier; Form row with a full-width custom button; `withAnimation(.spring)` literal; text fields with no explicit foreground in a scheme-dependent context.

Before screenshots: `.planning/phases/05-v1-1-safety-chat-and-ui-rebuild/screens/05-08/before/{pairing,list,settings,new-session}.png`

## impeccable audit + swiftui-pro (after), Task 3

Audit (native, single-context degraded as above):

| # | Dimension | Score | Key finding |
|---|---|---|---|
| 1 | Accessibility | 4 | Labels on every control, rows one combined element, XXL wraps, Reduce Motion honoured, AA |
| 2 | Performance | 3 | LazyVStack; ConnectionBanner still uses a Timer.publish ticker (pre-existing) |
| 3 | Theming | 3 | Tokens throughout; light-only by decision (DESIGN.md), not dark-adaptive |
| 4 | Platform conformance | 4 | System nav stack, sheet, confirmation dialog, 44 pt targets, SF Symbols |
| 5 | Adaptivity | 3 | iPhone-only target; ViewThatFits rows for large type |
| **Total** | | **17/20** | Good |

Found in the inspection round, all fixed in one batch (5e4e3df):
- Settings push status values rendered in mono (mono is reserved for codes and paths). Fixed with `rows(..., mono: false)`.
- The raw iOS push error ("no valid aps-environment…") had no context. It is now prefixed "This phone couldn't register for push: …".
- Pairing helper inline-code markdown rendered with odd spacing. Replaced with quoted “hub pair”.
- swiftui-pro: the Start button's accessibility hint was an empty string once a folder was chosen. It now reads "Starts Claude in the chosen folder".

The confirmation round (one) was clean. Not changed (suggested separately): `ToastCenter` still uses `ObservableObject`/`@Published` (pre-existing, used by ChatView too), and the banner ticker could become a `TimelineView`.

## Screenshots (mock-hub fixture data only, T-05-26)

All final shots were captured with the simulator in **dark** appearance, which proves the no-black rule holds:
- Default: `screens/05-08/{list,pairing,settings,new-session}.png`
- XXL: `screens/05-08/{list,pairing,settings,new-session}-xxl.png`
- Mid-plan (after Task 2, before audit fixes): `screens/05-08/rebuild/*.png`
- Before: `screens/05-08/before/*.png`

(Paths are relative to `.planning/phases/05-v1-1-safety-chat-and-ui-rebuild/`.) To regenerate: run the mock hub on 8799, then `TEST_RUNNER_SCREENSHOT_DIR=<dir> [TEST_RUNNER_SCREENSHOT_XXL=1] xcodebuild test … -only-testing:EchoR2UITests/ScreenshotUITests`.

## Test results (final run, `sh app/scripts/test.sh all`)

- unit: `Executed 41 tests, with 0 failures (0 unexpected)` ** TEST SUCCEEDED **
- snapshot: `Executed 1 test, with 0 failures (0 unexpected)` ** TEST SUCCEEDED **
- ui: `Executed 11 tests, with 2 tests skipped and 0 failures (0 unexpected)` ** TEST SUCCEEDED ** (skipped: opt-in testLiveHubSend and opt-in ScreenshotUITests)

Acceptance greps: no `Color.black`/`.black)` in Views or DesignSystem; no `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` in Views; no `.spring` literals in Views; SessionsListView has 5 `accessibilityLabel`s; DESIGN.md is over 40 lines; `static func send` and `accessibilityReduceMotion` are present.

## Deviations from Plan

1. **[Rule 1 - Bug] Black background root cause.** Not a black fill in code: the app never pinned a colour scheme, so the system-drawn containers went black in dark mode. Added `UIUserInterfaceStyle: Light` to `app/project.yml` (file not listed in the plan) and `screenBackground()` inside the stack.
2. **[Rule 2 - a11y] Typography moved to Dynamic Type text styles** (Typography.swift is not in the plan's file list). This was required for D-14 XXL. It also affects ChatView and SessionDetailView (they scale now).
3. **[Rule 3 - Blocking] Mock hub `GET /sessions/roots`.** Without it, New Session could only render its error state, so the picker could not be designed or captured. This is fixture data only.
4. **[Rule 3] Opt-in `ScreenshotUITests.swift`.** XcodeBuildMCP UI-automation tools were not exposed to this executor. Screenshots are captured through XCUITest instead, skipped unless `SCREENSHOT_DIR` is set.
5. **Token renames rippled to non-plan files** (AppModel, SessionDetailModel, Toast): mechanical `Haptics.*` and `AnimationToken` to `Motion` renames so each commit builds. Workout leftovers were deleted (felt* colours, StepperButton, TimeMinSecField, Chip, SectionHeader, OrnamentDivider, Eyebrow, cascadeReveal, breathingPulse).
6. **Snapshot re-record** (`testSessionsList.light.png`) for the intentional row and title change. Recorded with `SNAPSHOT_RECORD=1`, then asserted green.
7. **Settings has no toggles** today, so `Haptics.toggle()` is used on the Other disclosure, the folder picker and the banner retry instead. No toggle was invented.
8. New accessibility identifier `sessions.new` was added to the + button. All 05-02 and 05-07 identifiers are unchanged.

SessionDetailView/ChatView/TerminalScreen are 05-09 scope. They inherit light mode, so they are no longer black, but they don't yet have `screenBackground()` (their stack background is system white).

## Known Stubs

None.

## Threat Flags

None. Presentation only; the mock route binds 127.0.0.1 with fixture paths, and the screenshot test is opt-in.

## Self-Check: PASSED

Files: app/DESIGN.md, ScreenshotUITests.swift, and the 8 final + 4 before + 8 rebuild PNGs all exist. Commits 15ad2c7, 3445cad and 5e4e3df exist on origin/main.
