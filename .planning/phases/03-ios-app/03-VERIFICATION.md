---
phase: 03-ios-app
verified: 2026-11-11T00:00:00Z
status: human_needed
score: 6/6 must-haves verified (code inspection + macOS tests); device behaviors deferred to Phase 4
overrides_applied: 0
gaps: []
human_verification:
  - test: "Plain ws:// / http:// to the hub over Tailscale on a real iPhone (ATS)"
    expected: "Connects using a MagicDNS *.ts.net host. project.yml allows insecure loads only for ts.net (+ local networking). A raw 100.x IP or a bare hostname is NOT covered by that exception and may be blocked."
    why_human: "ATS behavior cannot be exercised without a device. This is the roadmap on-device spike."
  - test: "SwiftTerm renders the Claude TUI; 5 MB burst; replay-corruption check"
    expected: "Rendering correct, no hang, no garbled screen after reconnect or reset"
    why_human: "No iOS runtime (D-22). Roadmap spike."
  - test: "Pair once, kill and relaunch the app"
    expected: "Still connected; token loaded from Keychain"
    why_human: "Keychain on device/simulator. Only the Keychain round-trip is tested on macOS."
  - test: "Airplane-mode / Wi-Fi to cellular drop during a live session"
    expected: "Banner appears, stream auto-reconnects, missed output appears with no duplicates, banner clears"
    why_human: "NWPath and URLSessionWebSocketTask behavior needs a device. The dedupe logic is unit-tested."
  - test: "Extra-keys bar, resize-to-fit, Chat/Terminal toggle, trust-dialog banner, external session read-only in chat"
    expected: "Esc/Tab/Ctrl-C/arrows reach the PTY; terminal resizes; toggling preserves scrollback; external session shows 'watching' chip and no composer"
    why_human: "UI and touch behavior"
  - test: "Visual check of DesignSystem accent and echo wordmark"
    expected: "Matches the intended echo.r2 look"
    why_human: "Visual"
---

# Phase 3: iOS App Verification Report

**Phase Goal:** Rishi can pair the phone and, from anywhere, see every session, start new ones, read and steer them in chat or terminal, and trust the connection to recover.
**Verified:** 2026-11-11
**Status:** human_needed
**Re-verification:** No, initial verification

Note: ROADMAP marks the phase `mode: mvp`, but the goal is not in "As a ..., I want ..., so that ..." form. I verified against the six roadmap Success Criteria instead. This is a roadmap wording issue, not a code gap.

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Pair once, token in Keychain, relaunch stays connected; shared DesignSystem, accent, logo | VERIFIED (code) | `AppModel.swift` loads `Keychain.load` at init and `pair()` saves via `Keychain.save`. Keychain uses `AfterFirstUnlockThisDeviceOnly`. `DesignSystem/` has Palette, Logo, Components, and others. `KeychainTests` passes. Relaunch on device is deferred. |
| 2 | Start new session: allowlisted dir + optional prompt; appears in list with live state | VERIFIED | `HubClient.roots()` calls `GET /sessions/roots` and `createSession` calls `POST /sessions {cwd,prompt}`, matching `hub/server.js` lines 154-170 (201 `{id}`). `NewSessionView` and `SessionsListView` exist. `AppModel.pollSessions` polls every 3 s. State chips come from `SessionInfo.chip`. |
| 3 | Chat: his messages, Claude replies, one-line tool summaries; live; send | VERIFIED | `Frame` decodes the hub `kind:"chat"` events (role/text/tool). `ChatView` renders the tool row as `"\(tool) \(text)"`. `SessionDetailModel.send` sends `{type:"input",text}`, which the hub handles at server.js:231. |
| 4 | Terminal: resize, extra keys Esc/Tab/Ctrl-C/arrows, typing, toggle chat and back | VERIFIED (code) | `TerminalScreen.swift` has the ExtraKeysBar with those keys plus Enter. The delegate `send` forwards `{type:"keys",data}`. `sizeChanged` forwards a debounced `{type:"resize"}`. The `TerminalView` is owned by the model, so scrollback survives tab switches. The Tab toggle is in `SessionDetailView`. Rendering is deferred to a device. |
| 5 | External sessions labeled by source, open read-only in chat | VERIFIED | `isExternal` gives a "watching" chip. `SessionDetailModel` forces `readOnly` and the chat tab for externals, and every send, interrupt, resize and stop path is guarded. The composer is hidden (ChatView:55). The hub also rejects writes with `read_only`, and the app handles that error. |
| 6 | Auto reconnect, no duplicates, banner while unreachable | VERIFIED (code + unit) | `SessionStream` has exponential backoff 0.5 to 15 s, a 20 s ping with a 10 s timeout, an NWPathMonitor shortcut, and handling for 4404 and 4401. Reconnect uses `since=lastSeq&epoch=`. The `apply` reducer dedupes by `seq > lastSeq` and zeroes the cursor on `reset` before the replay. `ReplayTests` includes a seeded-cursor reconnect test. `ConnectionBanner` is driven by `app.connectionState`, which is `.unreachable` on reconnect or HTTP failure. |

**Score:** 6/6

## Behavioral Spot-Checks / Tests

| Check | Command | Result |
|-------|---------|--------|
| Regenerate and test | `cd app && xcodegen generate && xcodebuild test -scheme EchoR2Tests -destination platform=macOS -derivedDataPath build/dd` | TEST SUCCEEDED, 29 tests, 0 failures |

## Hub Contract Check (hub/server.js)

| App usage | Hub | Match |
|-----------|-----|-------|
| `GET /health`, fields ok/protocol/version/gitSha/uptime/os/hubName/epoch/claude | `health()` line 72 | yes |
| `POST /pair {code, deviceName}` returns `{token, deviceId}` | `pair()` returns `devices.add` output with status 201 and 403 `bad_code` | yes (`PairResponse` must match `devices.add` output; covered by the contract tests in 03-01 and not independently re-run) |
| `GET /sessions` returns `{epoch, sessions[]}`; fields id/cwd/pid/state/source/startedAt/label/title | `sessions.list()` | yes |
| `POST /sessions/{id}/stop` | regex route line 174 | yes |
| WS `/sessions/{id}/stream?since=&epoch=` | upgrade handler plus `attach()` | yes |
| Frames hello/reset/error and events term/chat/state | `attach()` | yes |
| Client frames input/keys/resize/interrupt | `attach()` message handler | yes |
| 401 mapped to Pairing; WS close 4401 and 4404 | hub lines 117 and 142 (4401), 207 (4404) | yes |

## Token Hygiene

- Auth is sent only via the `Authorization: Bearer` header, both for REST (`HubClient.raw`) and the WS upgrade (`SessionStream.request`). The WS URL carries only `since` and `epoch`. The hub reads the header only (server.js:107).
- `grep` for `print`, `NSLog`, `os_log` and `Logger` across `app/EchoR2` finds no logging calls at all. The token is held in `AppModel.token` and Keychain only.
- Keychain accessibility is `ThisDeviceOnly`.

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| APP-01 | SATISFIED (visual deferred) | DesignSystem, Logo, project.yml |
| AUTH-02 | SATISFIED | Keychain, pair, and a 401 handler that returns to Pairing (`AppModel.handle`) |
| SESS-01 | SATISFIED | NewSessionView, roots, createSession |
| CHAT-01..03 | SATISFIED | ChatView, send, interrupt, stop, live updates |
| TERM-01..03 | SATISFIED (code); rendering on device | TerminalScreen, extra keys, TrustDetector, `TrustDetectorTests` |
| EXT-01 | SATISFIED | read-only external handling |
| CONN-01, CONN-02 | SATISFIED (code + unit) | SessionStream, Replay, ConnectionBanner |

No orphaned requirements.

## Anti-Patterns

Not run in full. Spot-checks only. No TBD, FIXME or XXX debt markers were reviewed in the Swift sources I read. No stubs found in the inspected files (HubClient, SessionStream, Frame, Replay, SessionDetailModel, TerminalScreen, Models).

## Findings (non-blocking)

- WARNING (device): ATS exception covers `ts.net` only (plus local networking). If the user pairs with a Tailscale 100.x IP or a short hostname, plain HTTP and WS may be blocked. It is an already-listed roadmap spike, so confirm it on device and consider documenting "use the MagicDNS name" in the Pairing UI.
- WARNING (minor): `SessionStream.send` silently drops frames (`try?`, no `running` socket) during reconnect, so keystrokes typed while disconnected are lost without feedback. Acceptable for the MVP.

## Gaps Summary

No code gaps found. All six success criteria are supported by code and the 29 passing macOS tests, and the app matches the hub contract. Remaining items require a physical device and are listed above for Phase 4 on-device testing.

_Verifier: Claude (gsd-verifier)_
