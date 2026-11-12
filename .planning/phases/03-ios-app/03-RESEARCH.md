# Phase 3: iOS App - Research

**Researched:** 2026-11-11
**Domain:** SwiftUI iPhone client (XcodeGen, SwiftTerm, URLSessionWebSocketTask) for the echo hub wire protocol v1
**Confidence:** MEDIUM-HIGH (hub contract HIGH, read from source; SwiftTerm API HIGH, read from v1.99.3 source; ATS behavior MEDIUM/ASSUMED; no simulator runtime on this Mac, see Environment)

<user_constraints>
## User Constraints (from CONTEXT.md)

Locked decisions D-01..D-21 are in `03-CONTEXT.md` and are authoritative; the planner must read them directly. Summary of the load-bearing ones:

- D-01 `app/project.yml` XcodeGen, target `EchoR2`, display name "echo", bundle `com.rishizamvar.echor2`, team `373D7DZ9NM`, iOS 17.0, Swift 6.0, `SWIFT_STRICT_CONCURRENCY: complete`, `GENERATE_INFOPLIST_FILE: YES`, automatic signing, test target `EchoR2Tests`.
- D-02 One SPM dependency: SwiftTerm, upToNextMinor. No other packages.
- D-04 Copy WorkoutCoach DesignSystem into `app/EchoR2/DesignSystem/`, visually identical; remove WorkoutCoach-specific pieces only if they don't compile.
- D-07/D-09 Host in UserDefaults, token in Keychain (`AfterFirstUnlockThisDeviceOnly`); `Authorization: Bearer` on REST and WS upgrade; 401 clears token, routes to Pairing.
- D-08 plain http/ws over Tailscale; ATS exception only as narrow as research finds necessary.
- D-11..D-13 HubClient (REST), SessionStream (WS, backoff 0.5 to 15 s, ping 20 s, seq dedupe, NWPathMonitor), `@MainActor @Observable` VMs, disconnect on background.
- D-14..D-20 Screens: Sessions list (poll /sessions every 3 s), New Session sheet, Session detail Chat|Terminal toggle, external read-only, trust-dialog banner, ConnectionBanner, Settings.
- D-21 Unit tests without network; no MockHub; live smoke against the running Mac hub.

### Claude's Discretion
File/folder layout inside `app/EchoR2/`, styling within DesignSystem, animations, empty states.

### Deferred Ideas (OUT OF SCOPE)
APNs, notification settings, deep links, resume/take-over UI, release script (Phase 4); glasses / Mac-PC switcher (v2); shared DesignSystem package.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| APP-01 | Shared DesignSystem + echo accent/logo | DesignSystem audit below: compiles with 2 edits (ConnectionBanner, Logo) |
| AUTH-02 | Token persists across restarts | Keychain helper; Pair contract |
| SESS-01 | Start session from phone | `GET /sessions/roots`, `POST /sessions` contract |
| CHAT-01/02/03 | Read, send, live chat | `chat` event shape; `input` frame; WS stream |
| TERM-01/02/03 | Terminal, extra keys, toggle | SwiftTerm API section |
| EXT-01 | External sessions read-only | `state:'external'`, `source`, `label`; hub returns `read_only` |
| CONN-01/02 | Reconnect w/o dupes; banner | Stream/replay semantics, close codes |
</phase_requirements>

## Summary

The hub contract is small and fully read from source (below). The app is a thin client: 6 REST calls, one WS per open session, v1 JSON envelope. SwiftTerm 1.99.3 (tag verified via `git ls-remote`) uses swift-tools 6.2 with `swiftLanguageModes: [.v6]`, i.e. it is built for Xcode 26 / strict concurrency; this Mac has Xcode 26.0.1 so it resolves. Its `TerminalViewDelegate` is `@MainActor`, which fits `@MainActor @Observable` view models.

Two environment surprises matter for planning: (1) this Mac has **no iOS Simulator runtime installed** (only the SDK) and **only ~5.5 GiB free disk**, so `xcodebuild test` against a simulator is not possible without freeing space and downloading a multi-GB runtime; (2) the hub's `hubName` is `Rishis-MacBook-Pro-2567.local`, while the tailnet MagicDNS short name is `rishis-macbook-pro` and IP `100.125.215.102`. Plan around (1) with a macOS-hosted logic test target and a `generic/platform=iOS Simulator` build; prefill the pairing host with `rishis-macbook-pro`, not `hubName`.

**Primary recommendation:** Put all non-UI logic (envelope models, seq/replay reducer, trust detector, Keychain helper, JSON decoding) in `app/EchoR2/Core/` (Foundation + Security only, no UIKit) and compile it into BOTH the app and a `platform: macOS` unit-test target, so D-21 tests run with plain `xcodebuild test -destination 'platform=macOS'` with no simulator.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|------------|-------------|-----------|-----------|
| Session state, PTY, transcript parsing | Hub (API/Backend) | — | App only renders events; never parse term bytes for chat |
| Auth (token verify, whois) | Hub | App Keychain | App stores token and attaches header |
| Replay/dedupe | Hub (ring + seq) | App (last seq, ignore seq <= last) | Both sides cooperate |
| Terminal emulation | App (SwiftTerm) | — | Hub streams raw bytes |
| Chat markdown render | App | — | `AttributedString(markdown:)` |
| Trust-dialog detection | App (pure fn on term stream) | — | D-18, no hub change |
| Reconnect/network | App | — | NWPathMonitor + backoff |

## Hub Contract (source of truth: hub/server.js, hub/auth.js, hub/sessions.js, hub/eventlog.js)

All routes on tailnet listener `100.125.215.102:8790` (also loopback `127.0.0.1:8790` for local dev, no auth required there). Tailnet requests: whois must succeed and match owner else `403 {"error":"forbidden"}`; then `/health` and `/pair` are open (post-whois); everything else needs `Authorization: Bearer <token>` else `401 {"error":"unauthorized"}`. All bodies JSON, `content-type: application/json`, max body 1 MiB. [VERIFIED: hub/server.js]

| Route | Request | Response |
|-------|---------|----------|
| `GET /health` | none | `200 {ok:true, protocol:1, version, gitSha, uptime:Double, os:"darwin"|"win32", hubName, epoch, claude:{ok, version}}` |
| `POST /pair` | `{code, deviceName}` (code normalized server-side: uppercase, strips space/dash, O->0, I/L->1; 5 wrong tries burn the code, 5 min TTL) | `201 {token, deviceId}`; bad/expired: `403 {error:"bad_code"}` |
| `GET /sessions` | — | `200 {epoch, sessions:[{id, cwd, pid, state, source, startedAt, label?, title?}]}` ; `state` in `starting|running|waiting|done|exited|stopped|external`; `source` in `hub|external`; `startedAt` format not verified (treat as optional, decode as flexible: try ISO8601 string, else number ms) ; `label`/`title` only meaningful for external; `title` may be absent for hub sessions (fall back to cwd basename) |
| `GET /sessions/roots` | — | `200 {roots:[{root:"/abs/path", dirs:["name",...]}]}` (dirs = non-dot subdirs, sorted, max 200; full path = root + "/" + dir; root itself is also a valid cwd) |
| `POST /sessions` | `{cwd, prompt?}` (prompt string <= 10000) | `201 {id}`; `400 bad_cwd|bad_prompt|bad_json`; `503 claude_unavailable`; `500 spawn_failed`; `413 too_large` |
| `POST /sessions/:uuid/stop` | — | `200 {ok:true}`; `404 not_found`; `409 read_only|not_running` |
| `WS /sessions/:uuid/stream?since=<seq>&epoch=<uuid>` | Authorization header on upgrade | see below |

Upgrade failures: `403`/`401` HTTP response before upgrade (no 4xx close code); unknown session: upgrade succeeds then close `4404 "unknown session"`; revoked device: server closes `4401 "revoked"` (admin revoke). Non-matching path: socket destroyed. [VERIFIED: hub/server.js]

Hub to client frames (all JSON text, `v:1`):
- `{v:1,type:"hello",id,epoch,seq,state}` always first. `seq` = current log head.
- `{v:1,type:"reset",epoch}` sent when `since` older than ring floor OR `epoch` param differs from hub epoch; immediately followed by the FULL ring (all kinds) then live. Client MUST wipe terminal + chat on `reset`.
- `{v:1,type:"error",code}` codes: `bad_frame`, `not_found`, `read_only`, `not_running`, `internal`.
- Events: `{v:1,seq,kind:"term",data:<base64 PTY bytes>}`, `{v:1,seq,kind:"state",state}`, `{v:1,seq,kind:"chat",role:"user"|"assistant",text,tool?}` (`tool` present = tool-use row, `text` is `"Name: arg"` already shortened). One monotonic `seq` across all kinds. Chat events carry no id; dedupe purely by `seq`.
- Replay: `since` omitted = 0 (everything in ring); events with `seq > since` sent. Hub ring cap 2 MB.

Client to hub frames: `{type:"input",text}` (whole message to the TUI; hub serializes pastes), `{type:"keys",data:<raw string written to PTY>}`, `{type:"resize",cols,rows}` (numbers; no reply), `{type:"interrupt"}`. Anything else gets `error bad_frame`. Hub pings every 20 s and terminates on missed pong (URLSessionWebSocketTask auto-answers pings). Hub drops sockets whose send buffer exceeds 1 MiB: client just reconnects with `since`. Hub PTY default 120x30; send `resize` after connect and on size change. External sessions: `input/keys/interrupt/stop` all answer `read_only`.

Observed live (Mac hub up, curl from this Mac): `http://127.0.0.1:8790/health` and `http://100.125.215.102:8790/health` both return 200 with `hubName:"Rishis-MacBook-Pro-2567.local"`, protocol 1, version 0.1.0, gitSha 9d9583a. [VERIFIED: curl]

## Standard Stack

### Core
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| SwiftTerm | `upToNextMinor` from 1.99.3 (tags 1.99.0..1.99.3 exist; latest 1.99.3) | Terminal view | Only dependency (D-02). Package.swift: tools 6.2, `swiftLanguageModes [.v6]`, iOS 14+; PNG dep only under `PortableGraphics` trait on non-Apple, argument-parser only for `termcast` executable [VERIFIED: raw Package.swift + git ls-remote] |
| URLSession / URLSessionWebSocketTask | system | REST + WS | no Starscream |
| Security (SecItem) | system | Keychain helper | no KeychainAccess |
| Network (NWPathMonitor) | system | reconnect trigger | |

XcodeGen on this Mac: 2.44.1 (STACK.md says 2.46.0 exists; not required). Xcode 26.0.1 (17A400), SDK iOS 26.0.

`project.yml` snippet: `packages: SwiftTerm: {url: https://github.com/migueldeicaza/SwiftTerm, upToNextMinor: 1.99.3}` and `dependencies: - package: SwiftTerm` on `EchoR2`. XcodeGen key is `upToNextMinorVersion: 1.99.3` (XcodeGen spec names: `from`, `majorVersion`, `minorVersion`, `exactVersion`, `branch`, `revision`; use `minorVersion: 1.99.3`). [ASSUMED: XcodeGen key names; planner verify with `xcodegen generate`]

## Package Legitimacy Audit

| Package | Registry | Age | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-------------|-----------|-------------|
| SwiftTerm | SwiftPM (GitHub tag) | years (migueldeicaza, widely used) | github.com/migueldeicaza/SwiftTerm | n/a (not npm/PyPI/crates; slopcheck does not cover SwiftPM) | Approved: URL given by locked D-02 and confirmed via git ls-remote |

Transitive packages resolved by SPM (swift-png, swift-argument-parser, swift-docc-plugin) are declared by SwiftTerm; swift-png only compiles under a non-Apple trait. No other packages. Removed: none. Flagged: none.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | build | yes | 26.0.1 | — |
| xcodegen | project gen | yes | 2.44.1 | — |
| iOS Simulator runtime | simulator tests, screenshots | **NO** (`simctl list runtimes` empty; only SDK `iphonesimulator26.0`) | — | build for `generic/platform=iOS Simulator`; logic tests on macOS target; or free disk then `xcodebuild -downloadPlatform iOS` |
| Disk | runtime download | **5.5 GiB free of 460** | — | free ~10+ GiB before any runtime download |
| Mac hub | live smoke | yes, live on 8790 | 0.1.0 | — |
| Tailscale | tailnet | yes; Mac `100.125.215.102 rishis-macbook-pro`; `iphone-14-pro-max 100.120.95.17` active | — | — |
| Physical iPhone on tailnet | real smoke | active in tailnet | — | install via Xcode device build (Phase 4 does TestFlight) |

Missing, blocking nothing but constrains verification: simulator runtime. Simulator networking (when a runtime exists): iOS Simulator shares the Mac's network stack, so `127.0.0.1:8790` (loopback listener, no bearer needed but `Host` must be `127.0.0.1:8790` or `localhost:8790` and no Origin) and `100.125.215.102:8790` (tailnet listener; whois of the Mac's own IP resolves to the owner) both work, as confirmed by curl from this Mac. The app must NOT use `rishis-macbook-pro` in the simulator unless Mac resolver handles MagicDNS (it does when Tailscale runs). Do not call `/pair` or `POST /sessions` in automated smoke. [reasoned from curl + hub source]

## Architecture Patterns

### System Architecture Diagram
```
 Pairing screen --POST /pair--> Hub tailnet listener --> token --> Keychain
        |
  AppModel (@MainActor @Observable: hub host, token, connectionState)
        |
  SessionsVM --GET /sessions (3s poll)--> HubClient (URLSession async)
        |  tap
  SessionDetailVM <---- SessionStream (actor) ---- URLSessionWebSocketTask
        |                  | hello/reset/events (seq dedupe, backoff, NWPath)
        |                  v
        |        Reducer(state, frame) -> {lastSeq, epoch, chat[], termChunks, sessionState}
        |-- Chat tab: bubbles + composer --send {input}--> stream
        |-- Terminal tab: SwiftTerm TerminalView <- feed(base64 decoded)
                          keystrokes/ExtraKeys -> {keys}; sizeChanged -> debounced {resize}
```

### Recommended Structure
```
app/
  project.yml            (gitignore *.xcodeproj)
  EchoR2/
    App/        EchoR2App.swift, AppModel.swift (host, token, connectionState, route)
    Core/       (Foundation+Security only; also compiled into macOS test target)
                Models.swift (Codable), Frame.swift (envelope enum + decoder),
                Replay.swift (pure reducer), TrustDetector.swift, Keychain.swift,
                HubClient.swift
    Net/        SessionStream.swift (actor; uses URLSession, Network)
    Views/      Pairing, SessionsList, NewSession, SessionDetail, ChatView, TerminalScreen, Settings
    DesignSystem/ (copied)
  EchoR2Tests/   (compiled for macOS: Core/ only)
```
Keep HubClient in `Core/` (pure URLSession, Foundation) so it can be exercised by decoding tests; keep `Network` (NWPathMonitor) in `Net/`.

### Pattern 1: Pure reducer for replay/dedupe (D-11, D-21)
`struct StreamState { var epoch: String?; var lastSeq: Int; }` and `func apply(_ f: Frame, to s: inout StreamState) -> [Effect]` where Effect = `.resetUI | .term(Data) | .chat(Chat) | .state(String)`. Rules: `hello` -> record epoch if nil; `reset` -> `lastSeq = 0`, epoch = frame.epoch, emit `.resetUI`; event with `seq <= lastSeq` -> drop; else `lastSeq = seq`. Unknown `kind` -> advance `lastSeq` but emit nothing (do not crash decoding: decode `kind` as String then switch; unknown fields ignored by Codable). Important: after `reset`, the hub replays the full ring starting at its floor, whose seq may be BELOW the old `lastSeq` only if epoch changed (hub restarted: seq restarts at 1). So `reset` must set `lastSeq = 0` BEFORE processing replayed events or they will all be dropped.

### Pattern 2: SessionStream actor
URL: `ws://host:8790/sessions/<id>/stream?since=<lastSeq>&epoch=<epoch>`; `var req = URLRequest(url:); req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")`; `session.webSocketTask(with: req)` (a custom Authorization header on the upgrade URLRequest is honored by URLSessionWebSocketTask; headers other than the reserved WS handshake ones pass through). [CITED: developer.apple.com URLSessionWebSocketTask; behavior widely used, MEDIUM]. Loop `try await task.receive()` -> `.string(s)`; `.data` ignore. Ping: `task.sendPing { err in }` every 20 s via a Task sleep loop; on error cancel and reconnect. Close: `task.closeCode` / delegate `urlSession(_:webSocketTask:didCloseWith:reason:)`: `4404` -> mark session gone, do NOT retry; `4401` -> treat like 401 (forget token, Pairing); other/abnormal -> retry. Upgrade rejected (403/401) surfaces as a receive() error; inspect `(task.response as? HTTPURLResponse)?.statusCode == 401` -> Pairing, else backoff. Backoff 0.5, 1, 2, 4, 8, 15 cap, reset to 0.5 after a received `hello`. Use `Task.sleep` and check `Task.isCancelled`. Wrap URLSessionWebSocketTask in the actor; frames cross isolation as `Sendable` structs. On `scenePhase != .active`: cancel task; on `.active`: reconnect with stored `lastSeq`/`epoch` (D-13).

### Pattern 3: SwiftTerm in SwiftUI (TERM-01/02)
Verified in v1.99.3 source: [VERIFIED: SwiftTerm source]
- `TerminalView` is a `UIScrollView` subclass (`open class TerminalView: UIScrollView, ...`), `init(frame:font:)` and `init(frame:font:options: TerminalOptions)`; scrollback via `TerminalOptions(scrollback: 5000)` (`public var scrollback: Int`). Use `TerminalView(frame: .zero, font: nil, options: TerminalOptions(scrollback: 5000))` or set `getTerminal().options` per version; planner verify exact init in Xcode autocomplete.
- Feed: `terminalView.feed(byteArray: ArraySlice<UInt8>)` (also `feed(text:)`), `@MainActor` and nonisolated variants exist at the Terminal level. Pass `ArraySlice(Data(base64Encoded: s) ?? Data())`.
- Delegate: `@MainActor public protocol TerminalViewDelegate: AnyObject` with required `sizeChanged(source:newCols:newRows:)`, `setTerminalTitle(source:title:)`, `hostCurrentDirectoryUpdate(source:directory:)`, `send(source:data: ArraySlice<UInt8>)`, `scrolled(source:position:)`, `requestOpenLink(...)`, `bell`, `clipboardCopy`, `rangeChanged`. Several have default implementations; implement the five required first and let the compiler list the rest. Convert send data to `String(decoding: data, as: UTF8.self)` for the `keys` frame.
- Built-in accessory: on iOS `TerminalView.inputAccessoryView` defaults to `TerminalAccessory` (a `UIInputView` with ESC, Ctrl toggle, Tab, arrows etc., `touchButton`, `keyboardButton`), created by `setupAccessoryView()`; it is replaceable by assigning `inputAccessoryView`. D-16 requires Esc, Tab, Ctrl-C, arrows, Enter. Recommendation: first try the built-in accessory (it covers Esc/Tab/Ctrl/arrows); if Ctrl-C and Enter are missing, replace with a small custom `UIInputView`/SwiftUI-hosted bar sending raw sequences: Esc `\u{1b}`, Tab `\t`, Ctrl-C `\u{03}`, Up `\u{1b}[A`, Down `[B`, Right `[C`, Left `[D`, Enter `\r`. Arrow keys must honor application cursor mode ideally (`\u{1b}OA`); Claude's TUI accepts `\u{1b}[A`. [ASSUMED]
- Colors: set `nativeBackgroundColor`/`nativeForegroundColor` for the dark ink surface (D-05); font via `font` property (mono).
- Wrap in `UIViewRepresentable` with a `Coordinator: TerminalViewDelegate`; hold the `TerminalView` in the VM/coordinator, not recreated on SwiftUI updates (recreation loses scrollback). Replay must be re-fed on view recreation: keep the raw term chunks in the model (bounded, e.g. last 2 MB, matching hub ring) or keep the TerminalView alive for the session detail's lifetime. Simplest: VM owns a `TerminalView` created once; Terminal tab just embeds it.
- `reset` -> `terminalView.getTerminal().resetToInitialState()` (verify name) or `feed(text: "\u{1b}c")`. `\u{1b}c` (RIS) is the safe fallback.
- Resize: `sizeChanged` fires on layout; debounce 250 ms then send `{type:"resize",cols,rows}`; also send once after hello.
- Swift 6: `TerminalView` is a UIView (main actor); keep all access on MainActor. Package builds in language mode 6 itself; app target in strict-complete is fine. Not build-tested here (no simulator runtime; SDK build not attempted for disk reasons): Wave 0 must compile a stub that imports SwiftTerm with `xcodebuild -destination 'generic/platform=iOS Simulator'`.

### Pattern 4: Trust-dialog detector (D-18)
`func detectsTrustPrompt(_ chunk: String, tail: inout String) -> Bool`: keep a rolling tail (last ~2 KB of decoded term text after stripping ANSI `ESC[...[A-Za-z]`), lowercase, match `"do you trust the files in this folder"` or `"trust this folder"`; PTY chunks can split the phrase so the rolling buffer is required. Clear the banner when the session `state` event changes to `running` after input, or when the tail no longer matches after a screen clear. Unit-test with split chunks and ANSI-interleaved text.

### Anti-Patterns
- Parsing term bytes for chat (use `chat` events).
- Optimistic local echo of sent messages with a different dedupe path: the transcript tail will emit the user message as a `chat` event; show a pending bubble only until a matching `user` event arrives, or skip optimistic echo (ponytail: skip, rely on event; latency is the transcript tail interval).
- Reconnecting on `4404`.
- Recreating TerminalView on every SwiftUI update.
- Polling /sessions on the list while detail is open.

## Don't Hand-Roll

| Problem | Use | Why |
|---------|-----|-----|
| Terminal emulation | SwiftTerm | VT100/xterm is huge |
| Markdown | `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))` | Native; block-level syntax (headers, lists) not rendered by inline mode; acceptable (D-16 forbids MarkdownUI). Code fences render as plain text in inline mode: style whole-line mono if text starts with "```" |
| Reconnect | NWPathMonitor + backoff loop | ~40 lines |
| Keychain | SecItem ~25 lines | |
| Base64 | `Data(base64Encoded:)` | |
| WS | URLSessionWebSocketTask | |

## Common Pitfalls

1. **No simulator runtime / low disk.** `xcodebuild test -destination 'platform=iOS Simulator,...'` fails. Mitigation: macOS logic target; `generic/platform=iOS Simulator` build for compile checks; flag a human/Phase 4 on-device run. Do not start a 8+ GB runtime download with 5.5 GiB free.
2. **Reset ordering** (see Pattern 1): set `lastSeq=0` on reset before applying replay; epoch change after hub restart restarts seq at 1.
3. **`reset` also fires on first connect with stale epoch**; first connect with no `epoch` param and `since=0` gets full ring without a `reset` frame; the UI must start empty.
4. **Terminal replay after reconnect only contains deltas**; do NOT clear terminal on ordinary reconnect, only on `reset`.
5. **Hub ring is 2 MB**: long absence means `reset` + full ring; feeding 2 MB into SwiftTerm should happen off the hot path in batches (chunk per runloop turn) to avoid UI hitching.
6. **Keys frame carries a String**: invalid UTF-8 bytes from SwiftTerm (rare, e.g. mouse reports) become U+FFFD; acceptable. Disable mouse reporting (`allowMouseReporting = false`) to avoid garbage sequences. [ASSUMED beneficial]
7. **401 anywhere** -> clear token; also on WS upgrade failure via `task.response`. 403 `forbidden` means whois/owner mismatch (not a token problem): show "Hub refused this device", do not wipe the token.
8. **`@Observable` + actor**: do not hand `TerminalView` or the VM into the actor; actor emits `AsyncStream<Frame>` consumed on MainActor.
9. **XcodeGen**: re-run `xcodegen generate` before every build (D-03); pbxproj gitignored; test target needs `GENERATE_INFOPLIST_FILE: YES` too.
10. **Background**: URLSession sockets die when suspended; D-13 handles; do not claim background streaming.
11. **Sessions list state `waiting`** is hub's heuristic; label chip "needs you". `hubName` in /health differs from the typed host; show both.
12. **Pairing 5 wrong tries burn the code**; on `bad_code` tell the user the code may be burned: "Get a new code".
13. **Auto-capitalize**: Pair code field `.textInputAutocapitalization(.characters)`, `.autocorrectionDisabled()`, mono; hub normalizes O/I/L so don't over-validate; send as typed uppercase.

## ATS (Info.plist) Recommendation

Facts: ATS blocks plain HTTP (and `ws://`, treated as http) to hostnames unless excepted. Apple documents `NSAllowsLocalNetworking` as covering unqualified hostnames and `.local` names; whether IP literals are exempt could not be confirmed from the Apple page in this session (fetch returned titles only). `100.x` CGNAT is not RFC1918 so it is not "local network" for the Local Network privacy prompt either, so `NSLocalNetworkUsageDescription` is not expected to be needed. [ASSUMED: all of this paragraph; verify on device/simulator]

Recommended minimal set, in `project.yml` `info.properties`:
```yaml
NSAppTransportSecurity:
  NSAllowsLocalNetworking: true          # unqualified host "rishis-macbook-pro", *.local
  NSExceptionDomains:
    ts.net:                              # MagicDNS FQDN *.<tailnet>.ts.net
      NSIncludesSubdomains: true
      NSExceptionAllowsInsecureHTTPLoads: true
```
Plus a documented fallback: if a `100.x` literal fails with `NSURLErrorAppTransportSecurityRequiresSecureConnection` (-1022), add `NSAllowsArbitraryLoads: true`. This is exactly what WorkoutCoach already ships (its comment states it probes MagicDNS short name, FQDN, Tailscale IP and works on this tailnet), so the fallback is proven on-device. Given a personal, non-App-Store-public tool, accepting the fallback is low risk. Decision for planner: ship the minimal set, add one verification step (hit `http://100.125.215.102:8790/health` from the app on simulator/device); if it fails, switch to arbitrary loads and note it in SUMMARY. Note `NSAllowsArbitraryLoads` with TestFlight: allowed (App Review is not required for internal TestFlight; external needs justification, N/A).

## DesignSystem Audit (D-04)

Files (919 lines): Animations, Atmosphere, Components, ConnectionBanner, Haptics, Logo, Palette, ShakeGesture, Spacing, Toast, Typography. Grep for WorkoutCoach/Exercise/AppModel/Workout types: only two hits.
- **ConnectionBanner.swift** depends on `@Environment(AppModel.self)` with `app.demoMode`, `app.connectionState` (`.unreachable(reason)`, `.unknown`, `.healthy`), `app.lastSuccessfulCall`, `app.bootstrap()`, and on `AnimationToken.medium`. Will NOT compile unless echo's `AppModel` provides the same members. Simplest: define echo `AppModel` (`@Observable @MainActor`) with `enum ConnectionState {unknown, healthy, unreachable(String)}`, `var connectionState`, `var lastSuccessfulCall: Date?`, `var demoMode = false`, `func bootstrap() async` (retry). Alternatively rewrite ConnectionBanner to take plain parameters. Recommend: keep file, provide those 4 members (cheapest, keeps the copy visually and behaviorally identical). Banner's amber "quiet for N s" after 45 s and red after 120 s was designed for polling backends; for echo, set `connectionState = .unreachable("Hub unreachable")` directly on failures and update `lastSuccessfulCall` on every successful REST call/WS frame. Check `AnimationToken` exists in Animations.swift (not grep-confirmed; compile will tell).
- **Logo.swift**: `AppMark` hard-codes `Text("WorkoutCoach")`; replace with echo wordmark per D-05 (serif italic "echo" + mono ".r2"). `LogoMark`/`HandDrawnUnderline` are standalone Shapes/Views.
- **Toast.swift**: standalone; modifier named `wcoachToasts()` (rename to `echoToasts()` optional).
- **Haptics/ShakeGesture**: UIKit only.
- Others (Palette, Typography, Spacing, Components, Atmosphere, Animations): standalone SwiftUI. Components includes `Card, PrimaryButton, SecondaryButton, Chip, Eyebrow, SectionHeader, OrnamentDivider, StepperButton, TimeMinSecField (workout-specific, delete), EmptyState`. `Chip` is reusable for state chips. Palette: canvas, paper, sage `primary`/`primaryDeep`, `accent` rose, semantic `success/warning/danger`, `ink`, `textOnDark`; Typography: `display/title/titleSmall` serif, `heading/body/callout/caption` rounded, `mono`, `eyebrow`; Spacing xs4 s8 m12 l16 xl24 xxl32, corners 8/12/20/28.
- Needs also: an `Assets.xcassets` with `AccentColor` and `LaunchBackground` colorsets (WorkoutCoach project.yml references `UIColorName: LaunchBackground`, `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`). Copy the WorkoutCoach `Assets.xcassets` colorsets, a placeholder AppIcon is optional until Phase 4 TestFlight.
Swift 6 strict-concurrency compile risk: `ToastCenter` is `ObservableObject` with `static let shared` (non-Sendable global): will likely error under strict-complete; fix with `@MainActor` on `ToastCenter` (WorkoutCoach compiles it under the same settings, so likely already handled). Confirm by compile.

## UI Design Contract (treat as UI-SPEC; from D-04..D-20)

Global: canvas `Palette.canvas` background with `Atmosphere`; cards `Card` (paper); primary actions `PrimaryButton` (sage `primaryDeep`); body rounded 16 pt; titles serif; copy terse (D-06). `ConnectionBanner` pinned top of root. `ToastCenter` for transient errors. Portrait only, iPhone only (`TARGETED_DEVICE_FAMILY: "1"`). Dynamic Type: use the Typography tokens; chat/term mono fixed.

State chip colors (existing semantic palette only): running = `primary` sage; waiting ("needs you") = `warning`; done = `success`; exited = `textMuted`; stopped = `danger` muted; external = `accent` rose with label (e.g. "Even Terminal"). Chip text: running / needs you / done / exited / stopped / watching.

1. **Pairing** (route when no token; also after 401). Elements: echo wordmark; hub host field (prefill `rishis-macbook-pro:8790`, editable, mono, no autocorrect); hub info card (after host entry, `GET /health` -> "hubName, os, gitSha", debounced; error "Can't reach hub"); 8-char code field (uppercase, mono, `.characters`); PrimaryButton "Pair" disabled until host valid and 8 chars. States: idle, checking hub, hub reachable (info card), pairing (spinner), error (`bad_code` "Wrong or expired code. Get a new one.", `forbidden` "Hub refused this device", unreachable). On success: store token, go to Sessions.
2. **Sessions list** (home). Nav title "echo"; toolbar: gear (Settings), "+" (New Session). Card per session: title (title ?? basename(cwd)), state chip, relative last activity (`startedAt` fallback; no `lastActivity` field exists in `/sessions`, so show relative `startedAt` as "started 5m ago" unless a later hub change adds activity; flag to planner), external label. Sorted: waiting first, running, done, others; externals last. Pull-to-refresh; 3 s poll while visible (cancel on disappear/background). States: loading (skeleton/`EmptyState`), empty ("No sessions. Tap + to start."), error with last-known data greyed (opacity 0.5) + banner, normal.
3. **New Session** (sheet). Project picker built from `/sessions/roots`: sections per root (root path as header, root itself selectable as "(this folder)", then dirs); search optional (skip, ponytail); multi-line first-prompt `TextEditor` (optional, limit 10000 chars); PrimaryButton "Start". States: loading roots, error retry, starting (spinner, disabled), error toasts (`bad_cwd`, `claude_unavailable` "Claude not available on hub", `spawn_failed`). On 201 dismiss and push the new session.
4. **Session detail**. Header: title, state chip (live from `state` events), overflow menu: Interrupt (sends `{interrupt}`), Stop (confirmation dialog "Stop this session?" calls `POST /stop`). Segmented control Chat | Terminal (persist per session id in UserDefaults, default Chat). External: Chat only, Terminal segment disabled, composer replaced by note "Watching, started in <label>", menu hidden. Exited/stopped hub sessions: composer disabled ("Session ended").
   - **Chat**: `ScrollViewReader` list; user bubbles right (sage tint), assistant left (paper card), markdown via `AttributedString`; tool rows compact mono caption (`Chat.tool != nil`), single line truncated; auto-scroll to bottom on new message unless user has scrolled up (track via a bottom sentinel `onAppear/onDisappear`), with a "Jump to latest" pill when not at bottom; trust banner (D-18) at top: "Claude is asking to trust this folder. Open Terminal to answer." with a button switching to Terminal. Composer: multi-line `TextField(axis: .vertical)` 1-5 lines + Send button (disabled when empty/disconnected); send -> `{input,text}`; clear field on send.
   - **Terminal**: dark ink background (the only dark surface) inside a paper-card frame; SwiftTerm view; extra-keys bar (Esc, Tab, Ctrl-C, arrows, Enter) above keyboard; scrollback 5000.
   - States: connecting (subtle "Connecting"), live, reconnecting (ConnectionBanner), session unknown (4404 -> "Session not found", back), read-only.
5. **Settings**: card "Hub" (host, hubName, os, gitSha, protocol, claude version from `/health`); destructive "Forget hub" (confirm; clears Keychain token + host, back to Pairing); app version/build; (Notifications is Phase 4).
6. **Connection UX**: `ConnectionBanner` on root; red when hub unreachable/WS failing; list greys last-known data; banner Retry triggers `bootstrap()` (re-poll + reconnect stream).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing or XCTest (XCTest recommended: works in `xcodebuild test`, Xcode 26.0.1) |
| Config | `app/project.yml` target `EchoR2Tests` with `platform: macOS`, `sources: [EchoR2Tests, EchoR2/Core]` (no UIKit in Core), `GENERATE_INFOPLIST_FILE: YES`, Swift 6 strict concurrency |
| Quick run | `cd app && xcodegen generate && xcodebuild test -project EchoR2.xcodeproj -scheme EchoR2Tests -destination 'platform=macOS'` |
| Compile check (app incl. SwiftTerm, UI) | `xcodebuild build -project EchoR2.xcodeproj -scheme EchoR2 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` |
| Full suite | both of the above; plus live smoke below |

Note: CONTEXT D-01 says test target `EchoR2Tests` as iOS unit tests; because no simulator runtime exists here, make `EchoR2Tests` the macOS-hosted logic target. If a runtime is later installed, it can be retargeted without code change.

### Phase Requirements to Test Map
| Req | Behavior | Type | Command | Exists |
|-----|----------|------|---------|--------|
| CONN-01 | seq dedupe, ignore seq<=last, reset zeroes lastSeq, epoch change | unit | `-only-testing:EchoR2Tests/ReplayTests` | Wave 0 |
| CHAT-01 | decode chat events incl. tool rows, unknown kind ignored, unknown frame type ignored | unit | `FrameTests` | Wave 0 |
| CHAT-03 | event ordering through reducer produces chat effects | unit | `ReplayTests` | Wave 0 |
| SESS-01 | decode roots JSON, build cwd paths, POST body encoding | unit | `ModelsTests` | Wave 0 |
| EXT-01 | decode `source:external,state:external,label` ; `read_only` error code decode | unit | `ModelsTests` | Wave 0 |
| AUTH-02 | Keychain save/load/delete round trip | unit (macOS keychain; may need `kSecUseDataProtectionKeychain` off; skip with XCTSkip on -34018) | `KeychainTests` | Wave 0 |
| D-18 | trust detector incl. split chunks/ANSI | unit | `TrustDetectorTests` | Wave 0 |
| TERM-01/02/03, APP-01, CONN-02 | UI compile + visual | build + manual/screenshot on device (no sim runtime) | generic iOS Simulator build | n/a |
| Live | `GET /health` and `/sessions` JSON decodes against live hub | manual smoke script: `curl http://127.0.0.1:8790/health`, `/sessions`, `/sessions/roots` fed through decoder tests as captured fixtures | fixtures in `EchoR2Tests/Fixtures/` | Wave 0 (capture fixtures now with curl; do NOT pair/create) |

### Sampling Rate
- Per task commit: macOS test command. Per wave merge: both commands. Phase gate: both green + user device smoke (pair, list, open session) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `app/project.yml`, `.gitignore` (xcodeproj), `EchoR2Tests` macOS target, fixtures from curl of live `/health`, `/sessions`, `/sessions/roots` (loopback needs no auth).
- [ ] Stub app importing SwiftTerm compiling for generic iOS Simulator (de-risks SwiftTerm + strict concurrency before any UI work).
- [ ] Decide runtime: free disk and `xcodebuild -downloadPlatform iOS` if screenshots wanted.

## Security Domain

| ASVS | Applies | Control |
|------|---------|---------|
| V2/V3 Auth/Session | yes | Bearer token from `/pair`; Keychain `AfterFirstUnlockThisDeviceOnly`; never in query string or logs (hub itself rejects query tokens) |
| V5 Input validation | yes | Decode with Codable defensively; cap prompt 10000; host field validated as host[:port] |
| V6 Crypto | no (transport is WireGuard via Tailscale) | no custom crypto |
| V9 Communications | partial | plain http/ws accepted by design D-08; mitigated by Tailscale tunnel + whois |

Threats: token leakage via logs (do not log headers/URLs with tokens; no token in URL); malicious/garbage terminal bytes (SwiftTerm handles; disable OSC 52 clipboard writes if exposed: implement `clipboardCopy` as no-op), link opening via terminal (`requestOpenLink`: ignore or require tap confirmation); forgetting hub on 401.

## State of the Art
| Old | Current |
|-----|---------|
| ObservableObject | `@Observable` (iOS 17) |
| Starscream | URLSessionWebSocketTask |
| SwiftTerm needing manual Swift 6 tweaks | 1.99.x is `.v6` language mode natively |

## Assumptions Log
| # | Claim | Section | Risk |
|---|-------|---------|------|
| A1 | ATS exempts/behaves per the exception set above for `100.x` literal, bare host, `*.ts.net` | ATS | App can't connect; fallback to `NSAllowsArbitraryLoads` (proven in WorkoutCoach) |
| A2 | XcodeGen SPM key is `minorVersion` | Stack | generate fails; trivially fixed |
| A3 | `TerminalView` init signature / `resetToInitialState` exact names | SwiftTerm | compile fix; fallback `feed(text:"\u{1b}c")` |
| A4 | Built-in TerminalAccessory lacks Ctrl-C/Enter | SwiftTerm | maybe no custom bar needed |
| A5 | `startedAt` JSON format | Hub contract | decode as flexible; capture fixture from live `/sessions` in Wave 0 |
| A6 | Arrow escape variant `ESC [ A` accepted by Claude TUI | SwiftTerm | use `ESC O A` if not |
| A7 | URLSessionWebSocketTask honors custom Authorization on upgrade | Stream | test against the loopback hub? loopback ignores auth; verify on tailnet listener from device/simulator with real token |
| A8 | Local Network privacy prompt not triggered for 100.x | ATS | add `NSLocalNetworkUsageDescription` |

## Open Questions (RESOLVED)
1. Last-activity timestamp for list rows: `/sessions` has no activity field. RESOLVED: D-23 — list shows relative `startedAt` (ISO8601 with fractional seconds, verified live); no hub change in Phase 3.
2. Simulator runtime: free disk (5.5 GiB free) and download, or verify on the physical iPhone? RESOLVED: D-22 — no runtime download; Core logic tested on a macOS `EchoR2Tests` target, app compiled with `generic/platform=iOS Simulator`; on-device verification in Phase 4.
3. Hub `hubName` vs MagicDNS name. RESOLVED: D-07/D-24 — pairing host prefilled with MagicDNS `rishis-macbook-pro:8790` (user-editable, not hubName); ATS = `NSAllowsLocalNetworking` + `ts.net` exception, `NSAllowsArbitraryLoads` fallback decided at the Phase 4 device check.

## Sources
- Source code (HIGH): `hub/server.js`, `hub/auth.js`, `hub/sessions.js`, `hub/eventlog.js`, `hub/transcript.js`, SKELETON.md
- SwiftTerm v1.99.3 tag cloned and read (iOS TerminalView, TerminalViewDelegate, TerminalOptions, TerminalAccessory) and raw `Package.swift` (HIGH); tag list via `git ls-remote` (HIGH)
- Local probes: `xcodebuild -version`, `xcodegen --version`, `simctl list`, `df -h`, `tailscale status`, curl to 127.0.0.1 and 100.125.215.102 (HIGH)
- WorkoutCoach-iOS `project.yml`, `Info.plist`, DesignSystem sources (HIGH)
- Apple ATS/TN3179 pages: fetch returned only titles; ATS claims are knowledge-based (LOW-MEDIUM)

## Metadata
**Confidence:** Hub contract HIGH; SwiftTerm API HIGH (source) but not compile-tested; ATS MEDIUM/ASSUMED; verification plan HIGH given env constraints.
**Research date:** 2026-11-11 | **Valid until:** ~2026-12-11 (SwiftTerm churns fast)
