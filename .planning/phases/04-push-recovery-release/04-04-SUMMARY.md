---
phase: 04-push-recovery-release
plan: 04
subsystem: ios-app
tags: [apns, push, deep-link, appdelegate]
requires: [04-01]
provides:
  - Core: PushToken, DeepLink, Health.push, PushRegistration/PushTestResponse
  - HubClient: registerPush, testPush, resume, takeover
  - AppDelegate (UNUserNotificationCenterDelegate), PushSetup.enable, AppModel.registerPush/open(sessionId:)
  - aps-environment entitlement
affects: [04-05]
key-files:
  created: [app/EchoR2/Core/Push.swift, app/EchoR2/App/AppDelegate.swift, app/EchoR2/EchoR2.entitlements, app/EchoR2Tests/PushTests.swift]
  modified: [app/project.yml, app/EchoR2/Core/Models.swift, app/EchoR2/Core/HubClient.swift, app/EchoR2/App/AppModel.swift, app/EchoR2/App/EchoR2App.swift]
requirements-completed: [NOTF-02, NOTF-03]
completed: 2026-11-12
---

# Phase 4 Plan 4: App push registration and deep link Summary

Paired app asks for notification permission, registers for remote notifications, sends `{token, env}` (sandbox in Debug, production otherwise) to POST /devices/push, shows foreground banners, and opens the session on tap via a uuid-validated `sessionId`.

## Commits
- 8a84a50 feat(04-04): Core push helpers, models, HubClient endpoints (+ PushTests)
- 2dfc237 feat(04-04): entitlement, AppDelegate, AppModel wiring

## Verification
- macOS: `Executed 34 tests, with 0 failures` / `** TEST SUCCEEDED **` (29 baseline + 5 PushTests). RED was observed first (compile failure: PushToken/DeepLink not found).
- iOS compile check (-target iphonesimulator workaround, Assets.xcassets moved aside and restored, `assets-restored` printed): `** BUILD SUCCEEDED **` under Swift 6 strict concurrency.
- Grep gates: no print/NSLog/os_log in app/EchoR2/App; Push.swift has no UIKit import.

## Deviations from Plan
None. RED/GREEN landed as one commit (RED could not compile, so it was not committable on its own).

## Known Stubs
None. Not verified on device: real APNs token delivery, permission prompt, tap-to-open (no simulator; needs device + .p8 key).

## Threat Flags
None beyond the plan's threat model.

## Self-Check: PASSED
