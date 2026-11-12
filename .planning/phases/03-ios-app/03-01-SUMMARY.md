---
phase: 03-ios-app
plan: 01
subsystem: ios-app
tags: [swiftui, xcodegen, swiftterm, keychain, pairing]
requires: []
provides:
  - app/ XcodeGen project (EchoR2 iOS 17 + EchoR2Tests macOS)
  - Core layer (Models, Keychain, HubClient) with fixture tests
  - AppModel (banner contract), Pairing and Settings screens, echo-branded DesignSystem
affects: [03-02, 03-03, 03-04, 03-05]
tech-stack:
  added: [SwiftTerm 1.99.1 (exact pin)]
  patterns: [Core compiled directly into macOS test bundle, @MainActor @Observable AppModel]
key-files:
  created:
    - app/project.yml
    - app/EchoR2/App/EchoR2App.swift
    - app/EchoR2/App/AppModel.swift
    - app/EchoR2/Core/Models.swift
    - app/EchoR2/Core/Keychain.swift
    - app/EchoR2/Core/HubClient.swift
    - app/EchoR2/Views/PairingView.swift
    - app/EchoR2/Views/SettingsView.swift
    - app/EchoR2/DesignSystem/ (11 files)
    - app/EchoR2Tests/ (ModelsTests, KeychainTests, LiveHubTests, Fixtures/*.json)
  modified: [.gitignore]
key-decisions:
  - "SwiftTerm pinned exactly to 1.99.1: 1.99.2/1.99.3 fail to compile on Xcode 26.0.1 (PowerlineRenderer.swift:386 Array + DropFirstSequence)"
  - "ASSETCATALOG_COMPILER_APPICON_NAME set to empty string (no icon until Phase 4)"
metrics:
  tasks: 4
  completed: 2026-11-11
---

# Phase 3 Plan 01: Project, Core, Pairing/Settings Summary

XcodeGen project with Swift 6 strict concurrency, a tested Core layer (Models, Keychain, HubClient), copied echo-branded DesignSystem, AppModel, and Pairing/Settings screens.

## Commits

- b7277ad: XcodeGen project, SwiftTerm probe, macOS test target
- dc3686d: Core layer with fixture tests
- a504c62: DesignSystem copy, echo wordmark, AppModel
- cb08008: app routing, Pairing and Settings screens

## Verification results

- macOS tests: 7 tests, 0 failures, 0 skipped (`xcodebuild test -scheme EchoR2Tests -destination platform=macOS`).
- **KeychainTests ran (not skipped).** Path used: the data-protection keychain returns -34018 (errSecMissingEntitlement) for the unsigned test bundle (confirmed with a standalone swift probe), so Keychain.swift falls back once to the login (file-based) keychain, where the round trip passes. On iOS the data-protection keychain is used with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- LiveHubTests ran (hub up) and passed; GET /health only.
- iOS app build: succeeded for the iphonesimulator SDK under Swift 6 strict concurrency, with SwiftTerm linked and compiled (probe in Task 1). See deviations for how it was built.

## Deviations from Plan

**1. [Rule 3 - Blocking] SwiftTerm version pin.** `minorVersion: 1.99.3` resolves but 1.99.3 (and 1.99.2) do not compile on Xcode 26.0.1. Pinned `exactVersion: 1.99.1` (last tag before the offending PowerlineRenderer line). Same package/URL. Revisit when Xcode is updated. (b7277ad)

**2. [Rule 3 - Blocking] iOS build command differs from plan.** This Mac has the iOS SDK but no simulator runtime/destinations, so `-destination 'generic/platform=iOS Simulator'` is rejected ("iOS 26.0 is not installed"). Verified instead with
`xcodebuild build -project EchoR2.xcodeproj -target EchoR2 -configuration Debug -sdk iphonesimulator -arch arm64 SYMROOT=app/build/sym -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO`.
Two extra workarounds were needed for verification only (not committed):
  - `-target` builds do not build SwiftTerm's build-tool plugin executable; I pre-built `SwiftTermBuildInfoGenerator` with `swift build` and copied it to `app/build/sym/Debug/`.
  - actool refuses to compile `Assets.xcassets` without a simulator runtime ("No available simulator runtimes"), so the catalog was moved aside during the build check. The two colorsets are unmodified copies from WorkoutCoach (which builds). The asset catalog is therefore NOT compile-verified here; verify on a machine with the iOS platform installed (or on device in Phase 4).

**3. [Rule 3] project.yml.** Added `ASSETCATALOG_COMPILER_APPICON_NAME: ""` (otherwise actool demands an AppIcon set). Added `app/build/` to .gitignore.

**4. DesignSystem edits (Task 3):** only Logo.swift (AppMark now serif italic "echo" + mono ".r2"; dropped "dumbbell" wording in a comment). No edits to Components.swift (TimeMinSecField compiles, left in) or Toast.swift (already `@MainActor`). Copied colorsets: AccentColor, LaunchBackground (no AppIcon).

## Known Stubs

None. RootView shows SettingsView when paired as a placeholder root by plan design; 03-02 replaces it with the Sessions list.

## Not verified (deferred to Phase 4 on-device)

Real pairing over Tailscale, relaunch stays paired, ATS acceptance of the bare MagicDNS host, and any visual check of the screens (no simulator available).

## Self-Check: PASSED
Files and commits b7277ad, dc3686d, a504c62, cb08008 exist.
