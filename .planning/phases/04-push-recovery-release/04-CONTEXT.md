# Phase 4: Push, Recovery & Release - Context

**Gathered:** 2026-11-12
**Status:** Ready for planning
**Mode:** --auto (user: "continue autonomously")

<domain>
## Phase Boundary

Hub sends APNs pushes (finish / needs input / exit / hub started) with deep links; sessions stopped by a hub restart can be resumed; external sessions can be taken over; the app ships to Rishi's iPhone via TestFlight and the deferred Phase 3 on-device checks run there. Hub = live Mac stand-in (launchd); PC parked.

Requirements: NOTF-01..05, SESS-06, EXT-02, APP-02. Also closes Phase 3 human verification items (03-VERIFICATION.md) on device.

</domain>

<decisions>
## Implementation Decisions

### APNs sender (hub)
- **D-01:** New `hub/apns.js` (stdlib only): `node:http2` session to `api.push.apple.com` (production) or `api.sandbox.push.apple.com`, reused; reconnect on `goaway`/`close`. JWT ES256 via `crypto.sign('sha256', …, {key, dsaEncoding:'ieee-p1363'})`, header `{alg:'ES256', kid}`, claims `{iss: teamId, iat}`, cached 45 min.
- **D-02:** Config in `~/.echo-hub/config.json`: `apns: {keyId, teamId: '373D7DZ9NM', keyPath, bundleId: 'com.rishizamvar.echor2'}`; `.p8` lives at `~/.echo-hub/AuthKey_<keyId>.p8` (mode 600, never in git). If unconfigured, push is disabled and `/health` reports `push: 'unconfigured'` — hub keeps working.
- **D-03:** Device push tokens: app registers `POST /devices/push {token, env: 'sandbox'|'production'}` (authed; bound to the paired deviceId). Stored alongside the device record in devices.json. Revoke removes them. 410 / `BadDeviceToken`/`Unregistered` → delete that push token. Retry once on 5xx / connection error.
- **D-04:** Payload: `{aps:{alert:{title, body}, sound:'default', 'thread-id': sessionId}, sessionId}`; header `apns-collapse-id: sessionId`, `apns-push-type: alert`, `apns-priority: 10`, `apns-topic: bundleId`. Title = session title or cwd basename (≤ 60 chars); body = one-line summary ≤ 140 chars: Stop → first line of `last_assistant_message`; Notification → hook `message`; exit → "exited (code N)". No full transcripts in pushes.
- **D-05:** When to push: state transitions to `done` (Stop, after existing 1.5 s debounce), `waiting` (Notification), `exited`; for external sessions too (global hooks). Per-session cooldown 10 s collapses rapid repeats (NOTF-04). No push while a paired app has that session's stream open and the app reported foreground? → skip for v1 (simple: always push; collapse-id dedupes on device).
- **D-06:** "hub started" push (NOTF-05) on every hub boot after the tailnet listener binds, to all registered tokens: title "echo hub", body "online · <hubName> · <gitSha>". Also `POST /admin/test-push` (loopback) + `cli test-push` for manual checks.

### Recovery (hub)
- **D-07:** `POST /sessions/:id/resume` (authed) for `stopped` (or `exited`) hub sessions: spawn `claude --resume <id>` in the original cwd with the same hooks/env scrub; new PTY, same session id if Claude keeps it (verify; if Claude forks a new id, map new id → keep hub id and record `claudeId`). State → running.
- **D-08:** `POST /sessions/:id/takeover` for `external` sessions: refuse 409 `busy` if transcript mtime < 60 s ago or a live pid in `~/.claude/sessions/*.json` references this session; else resume inside hub (same as D-07) and drop the external record. App shows a confirm sheet explaining "stop it on the other device first".
- **D-09:** CLI: `cli resume <id>`, `cli takeover <id>`.

### App
- **D-10:** Push: `UIApplicationDelegateAdaptor` AppDelegate; request authorization after pairing; `registerForRemoteNotifications`; send token + env (`#if DEBUG` → sandbox else production; TestFlight = production) via `POST /devices/push`. Entitlement `aps-environment` (development for debug; Xcode automatic signing switches to production on archive).
- **D-11:** Tap → `userNotificationCenter(_:didReceive:)` reads `sessionId` → AppModel navigates to that session (deep link), fetching sessions first if needed. Foreground presentation: banner + sound.
- **D-12:** Session detail overflow menu: "Resume" for stopped/exited, "Take over" for external (confirm sheet; show 409 busy message). Settings: notifications status + "Send test push" (calls loopback-only admin? no — add authed `POST /devices/push/test` that pushes only to the caller's tokens).
- **D-13:** Background: unchanged — sockets close in background; pushes carry the signal.

### Release
- **D-14:** `app/scripts/release.sh`: bump `CURRENT_PROJECT_VERSION` (timestamp-based or +1 in project.yml), `xcodegen generate`, `xcodebuild archive -allowProvisioningUpdates -destination generic/platform=iOS`, `-exportArchive` with `ExportOptions.plist` (`method: app-store-connect`, `destination: upload`, `teamID: 373D7DZ9NM`, automatic signing). Mirror WorkoutCoach `scripts/build_distribution.sh`. Disk: delete `app/build/` archive after successful upload.
- **D-15:** Human steps (cannot be automated; one checkpoint): (1) create APNs Auth Key in developer.apple.com → Keys (APNs) and place `.p8` at `~/.echo-hub/` + tell Key ID; (2) create the App Store Connect app record for bundle id `com.rishizamvar.echor2` (name "echo.r2"; SKU echor2); (3) ensure Xcode is signed in to the team for `-allowProvisioningUpdates`; (4) install from TestFlight, pair with `node hub/cli.js pair`, allow notifications; (5) run the on-device checklist (03-VERIFICATION human items + push + resume/takeover). (6) iPhone Tailscale key expiry (2026-11-24).
- **D-16:** If the ATS `ts.net` exception fails on device for any host form, switch to `NSAllowsArbitraryLoads` (WorkoutCoach precedent) in a follow-up commit and re-release.

### Testing
- **D-17:** Hub: `hub/hub.test.js` covers JWT shape (verify signature with generated EC key), payload builder truncation, cooldown/collapse, 410 token deletion (stub http2 via injectable `send` fn), resume/takeover routes incl. 409 busy (fake claude). App: macOS tests for push-token hex encoding + deep-link routing reducer. Live: `cli test-push` to the phone after D-15.

### Claude's Discretion
- Exact cooldown numbers, payload wording, file split (keep `apns.js` the only new hub file), Settings layout.

</decisions>

<canonical_refs>
## Canonical References
- `.planning/ROADMAP.md` §Phase 4, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`
- `.planning/phases/03-ios-app/03-VERIFICATION.md` — on-device checklist to close here
- `.planning/phases/02-secure-hub-install-mac-stand-in-pc/02-02-SUMMARY.md` (devices.json, auth), `02-03-SUMMARY.md` (ext hooks)
- `hub/server.js`, `hub/sessions.js`, `hub/auth.js`, `hub/hooks.js`, `hub/RUNBOOK.md`
- `app/project.yml`, `app/EchoR2/App/AppModel.swift`
- `/Users/rishizamvar/Documents/Projects/WorkoutCoach-iOS/scripts/build_distribution.sh`, `ExportOptions.plist`
- `.planning/research/STACK.md` §APNs, `.planning/research/PITFALLS.md` (APNs env mismatch, TestFlight 90-day expiry)
</canonical_refs>

<code_context>
## Existing Code Insights
- sessions.js already has `stopped` boot transition and a state machine; resume reuses the spawn path.
- Hooks already deliver Stop/Notification (owned via `--settings`, external via global ext hook).
- Default app host is now `rishis-macbook-pro.tail748eb9.ts.net:8790` (ATS ts.net exception).
- Mac disk ~5.5 GB free — archive builds fit but clean up after.
</code_context>

<specifics>
## Specific Ideas
- Push copy terse and glasses-friendly (G2 mirrors iPhone notifications).
</specifics>

<deferred>
## Deferred Ideas
- Approve/deny permission prompts from push (v2, reuses Notification plumbing)
- Live Activities, widgets
- PC verification plans (01-05, 01-06, 02-07) until PC returns
</deferred>
