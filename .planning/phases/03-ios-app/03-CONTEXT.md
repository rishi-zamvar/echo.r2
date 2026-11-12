# Phase 3: iOS App - Context

**Gathered:** 2026-11-11
**Status:** Ready for planning
**Mode:** --auto (user: "continue autonomously")

<domain>
## Phase Boundary

SwiftUI iPhone app `echo.r2` that pairs with the hub, lists sessions, starts new ones, shows each session as Chat and Terminal (toggle), watches external sessions read-only, and reconnects cleanly. Hub is the live Mac stand-in (`rishis-macbook-pro`, 100.125.215.102:8790); PC hub later — app must not hard-code either.

Requirements: APP-01, AUTH-02, SESS-01, CHAT-01, CHAT-02, CHAT-03, TERM-01, TERM-02, TERM-03, EXT-01, CONN-01, CONN-02. Push/APNs, resume/take-over UI, TestFlight release script → Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Project
- **D-01:** Code lives in `echo.r2/app/`: `app/project.yml` (XcodeGen; pbxproj gitignored), target `EchoR2`, display name "echo", bundle id `com.rishizamvar.echor2`, team `373D7DZ9NM`, iOS 17.0, Swift 6.0, `SWIFT_STRICT_CONCURRENCY: complete`, `GENERATE_INFOPLIST_FILE: YES`, automatic signing. Test target `EchoR2Tests`. Mirror WorkoutCoach-iOS/project.yml conventions.
- **D-02:** One SPM dependency: SwiftTerm (`https://github.com/migueldeicaza/SwiftTerm`, upToNextMinor from the latest 1.x that resolves; research verifies). No other packages.
- **D-03:** Build/test: `xcodegen generate` then `xcodebuild` against an iPhone simulator (per ZeeChat-era lesson: always regenerate before building). Unit tests run on simulator without network.

### Design language
- **D-04:** Copy `WorkoutCoach-iOS/WorkoutCoach/DesignSystem/` (Palette, Typography, Spacing, Components, Atmosphere, ConnectionBanner, Toast, Haptics, Animations, Logo, ShakeGesture) into `app/EchoR2/DesignSystem/` and keep it visually identical (apothecary editorial: lavender canvas, cream paper cards, sage primary, serif display + rounded body). Remove WorkoutCoach-specific pieces only if they don't compile. Shared-package extraction is out of scope (ponytail: copy now, extract when a 3rd app needs it).
- **D-05:** echo.r2 identity: replace `Logo` with an "echo" wordmark (serif italic "echo" + small ".r2" in mono). Accent for echo.r2 = existing `Palette.primaryDeep` sage for actions; session state colors use existing semantic colors. Terminal view: dark ink background inside a paper card, mono font — the only dark surface.
- **D-06:** Glasses/terse-friendly copy everywhere: short labels, no jargon.

### Hub connection & config
- **D-07:** Hub address entered once at pairing (default prefilled `rishis-macbook-pro` MagicDNS name and port 8790; editable) and stored in UserDefaults; token stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, ~25-line helper). Multiple hubs out of scope (one active hub; changing hub = re-pair).
- **D-08:** Transport: plain `http://` / `ws://` over Tailscale. Add ATS exception scoped narrowly (`NSAppTransportSecurity` → `NSAllowsLocalNetworking` + exception domains for the hub host / `ts.net`) only as research determines necessary. On-device verification in Phase 4 / when Rishi installs.
- **D-09:** Auth: `Authorization: Bearer <token>` on every REST call and on the WebSocket upgrade `URLRequest`. 401 anywhere → clear token, route to Pairing.
- **D-10:** Pairing screen: hub host field + 8-char code field (auto-uppercase, monospaced) → `POST /pair {code, deviceName: UIDevice.name}` → store token. Shows hub `/health` (hubName, os, gitSha) before pairing so user sees which hub they're on.

### Data & networking layer
- **D-11:** `HubClient` (REST: health, sessions list, roots, create, stop) with `async/await` URLSession. `SessionStream` wraps `URLSessionWebSocketTask`: connect with `since=<lastSeq>&epoch=<epoch>`, receive loop, decode v1 envelope (`hello`, `reset`, events kind `term|chat|state`, `error`), send frames `input|keys|resize|interrupt`. Ping every 20 s; on failure reconnect with exponential backoff (0.5 s → 15 s) using last seen seq; dedupe by seq (ignore seq ≤ last). `NWPathMonitor` triggers immediate reconnect on network change.
- **D-12:** Swift concurrency: `@MainActor @Observable` view models; stream on a dedicated actor; Sendable models. Follow swift-concurrency skill guidance.
- **D-13:** App lifecycle: disconnect sockets when backgrounded, reconnect + replay on foreground (push covers background in Phase 4).

### Screens
- **D-14:** Sessions list (home): cards per session — title (or cwd basename), state chip (running / waiting for you / done / exited / stopped / external + label like "Even Terminal"), relative last activity. Pull to refresh + live updates via polling `/sessions` every 3 s while visible (no list WS in protocol v1). "+" opens New Session.
- **D-15:** New Session sheet: project picker from `GET /sessions/roots` (roots + subdirs), optional first prompt (multi-line), Start → `POST /sessions` → navigate to the session.
- **D-16:** Session detail: segmented toggle Chat | Terminal (default Chat; remember last choice per session). Header: title, state chip, overflow menu (Interrupt, Stop with confirm).
  - Chat: bubbles — "you" right, Claude left (markdown rendered via `AttributedString(markdown:)` — no MarkdownUI dep), tool lines as compact mono rows. Composer at bottom (multi-line, Send). Auto-scroll on new messages unless the user scrolled up.
  - Terminal: SwiftTerm `TerminalView` via `UIViewRepresentable`; feed base64-decoded term bytes; keystrokes → `keys` frames; size changes → debounced `resize`. Extra-keys bar above keyboard: Esc, Tab, Ctrl-C, ↑ ↓ ← →, Enter. Cap scrollback (~5000 lines).
- **D-17:** External sessions: open read-only — Chat only, composer replaced by "Watching — started in <label>" note; Terminal tab disabled.
- **D-18:** Folder-trust stall (STATE todo): if the terminal stream contains Claude's trust-dialog text ("Do you trust the files in this folder" / "trust this folder"), show a banner in Chat: "Claude is asking to trust this folder — open Terminal to answer." Terminal view lets the user pick Yes. No hub changes needed; detection is a pure function with a unit test.
- **D-19:** Connection: `ConnectionBanner` (from DesignSystem) shown when hub unreachable or reconnecting; list shows last known data greyed.
- **D-20:** Settings: hub info, re-pair/forget hub, app version. Notifications settings come in Phase 4.

### Testing
- **D-21:** Unit tests (no network): envelope decoding (all frame types incl. unknown kind ignored), seq dedupe/replay logic, reset handling, trust-dialog detector, Keychain helper round-trip, roots/session JSON decoding. A `MockHub` is NOT built — UI verified by simulator build + screenshots via XcodeBuildMCP if available; live smoke against the running Mac hub from the simulator (simulator shares the Mac's network/Tailscale, so `http://100.125.215.102:8790` and loopback both work — research confirms).

### Post-research decisions (auto)
- **D-22:** No iOS Simulator runtime on this Mac and ~5.5 GB free disk → do NOT download a runtime. Verification = (a) logic in `app/EchoR2/Core/` (Foundation + Security only) compiled into both the app and a `platform: macOS` test target `EchoR2Tests`, run with `xcodebuild test` on macOS; (b) `xcodebuild build -destination 'generic/platform=iOS Simulator'` (and `generic/platform=iOS`) for UI + SwiftTerm compile checks; (c) on-device verification on Rishi's iPhone in Phase 4 (TestFlight). Wave 0 compiles a SwiftTerm stub first.
- **D-23:** Session list shows relative `startedAt` (no hub change in Phase 3).
- **D-24:** ATS: `NSAllowsLocalNetworking` + `ts.net` exception domain (subdomains, insecure HTTP). Default host = MagicDNS `rishis-macbook-pro` (not hubName). If on-device test shows 100.x literal/bare host blocked, fall back to `NSAllowsArbitraryLoads` (WorkoutCoach precedent) — decided in Phase 4 device check.
- **D-25:** WS close 4404 = session gone (don't retry), 4401 = revoked (go to pairing). On `reset`, set lastSeq=0 before applying replay.

### Claude's Discretion
- File/folder layout inside `app/EchoR2/`, exact component styling within the copied DesignSystem, animation choices, empty states.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` §Phase 3, `.planning/STATE.md` (todos)
- `.planning/phases/01-hub-session-engine/SKELETON.md` — wire protocol v1 (frames, REST)
- `.planning/phases/02-secure-hub-install-mac-stand-in-pc/02-0{1,2,3}-SUMMARY.md` — auth, pair, roots, health shapes
- `hub/server.js`, `hub/auth.js`, `hub/cli.js` — source of truth for routes/frames
- `hub/RUNBOOK.md` — pairing flow
- `/Users/rishizamvar/Documents/Projects/WorkoutCoach-iOS/project.yml` and `WorkoutCoach/DesignSystem/` — conventions + design system to copy
- `.planning/research/STACK.md` (iOS section), `.planning/research/PITFALLS.md` (iOS background sockets, SwiftTerm)

</canonical_refs>

<code_context>
## Existing Code Insights

- DesignSystem is ~919 lines, SwiftUI + UIKit (Haptics) only, no external deps.
- WorkoutCoach uses Swift 6 strict concurrency, iOS 17, automatic signing with team 373D7DZ9NM.
- Hub REST: `GET /health`, `POST /pair`, `GET /sessions`, `GET /sessions/roots`, `POST /sessions`, `POST /sessions/:id/stop`; WS `/sessions/:id/stream?since=&epoch=`.

</code_context>

<specifics>
## Specific Ideas

- "Spy kid" personal + discreet vibe through naming and the wordmark, not through a new visual language — user explicitly wants the shared design language.

</specifics>

<deferred>
## Deferred Ideas

- APNs, notification settings, deep links, resume/take-over UI, release script → Phase 4
- Glasses integration / Mac↔PC switcher → v2
- Shared DesignSystem SPM package → when a third app needs it

</deferred>
