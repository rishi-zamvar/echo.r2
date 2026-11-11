# Technology Stack

**Project:** echo.r2 (iPhone remote for Claude Code agents on a Windows PC hub)
**Researched:** 2026-11-11
**Philosophy:** ponytail. Node stdlib first, 2 runtime npm deps on the hub, 1 SPM dep in the app.

Versions below were checked against the npm registry, nodejs.org/dist and GitHub releases on 2026-11-11 (HIGH for "version exists"). Behavioral claims are marked individually.

## Recommended Stack

### Hub: runtime and core (Windows, Node)
| Technology | Version | Purpose | Why | Confidence |
|---|---|---|---|---|
| Node.js | 24.x LTS "Krypton" (24.22.3) | Hub runtime | Active LTS, listed in node-pty `engines` (20/22/24/26). Node 26 "Lithium" (26.13.1) is also flagged LTS in the dist index, but 24 has more miles with native addons. Pin 24, revisit later. | HIGH (version), MEDIUM (24 vs 26 call) |
| node-pty | 1.1.0 | ConPTY spawn of `claude` | Only maintained ConPTY binding (Microsoft). Requires Windows 10 1809+; winpty removed. Depends only on node-addon-api. Same lib Even Terminal-class tools use. | HIGH |
| ws | 8.22.2 | WebSocket server | Node still has no built-in WS server. `ws` is the de facto standard, zero deps, shares the `http.Server` so one port serves REST + WS. | HIGH |
| `node:http` | stdlib | REST (`POST /sessions`, pairing, hook receiver) | Handful of routes. No Express/Fastify. | HIGH |
| `node:http2` + `node:crypto` | stdlib | APNs sender, .p8 token auth | See "APNs" below. No `@parse/node-apn` (8.2.0 exists but is a dependency tree for ~60 lines of work). | HIGH |
| `node:fs` (`fs.watch` + byte-offset reads) | stdlib | Transcript JSONL tail | Per-file `{offset}` + read-new-bytes + split on `\n`. Keep partial last line buffered. No chokidar (6.0.0). | MEDIUM |
| `node:test` + `node:assert` | stdlib | The one test file | Spec asks for one runnable test file. No Jest/Vitest. | HIGH |
| JSON file store (atomic write: write tmp then `rename`) | stdlib | Sessions, device tokens, APNs tokens | Single user, tens of records. Spec allows JSON or SQLite. `better-sqlite3` (13.1.1) is a native addon on Windows = second build-toolchain risk. If ever needed, `node:sqlite` is built in. | HIGH |
| `node:child_process.execFile` -> `tailscale.exe whois --json <ip>` | stdlib + installed CLI | Tailscale peer identity check | See "Tailscale whois" below. | MEDIUM |

Runtime npm deps total: **node-pty, ws**. That is it.

### Hub: scrollback and seq replay (no library)
- Per session: `events[]` ring (bounded, e.g. last N events or ~1 MB) with monotonic `seq`. Terminal view stores raw PTY chunks; chat view stores parsed transcript messages. Client sends `since=<seq>`; hub replays then streams. If `since` is older than ring start, send a `reset` frame so the app clears the terminal and re-renders from the ring.
- Send PTY bytes as WS **binary** frames (or base64 in JSON if you want one frame type; binary is cheaper and SwiftTerm wants `[UInt8]`/`ArraySlice<UInt8>`). Control (resize, input, seq) as JSON text frames.
- Add WS ping every ~20s from the hub (`ws` `ping()`), terminate on missed pong. Phones on cellular silently half-close sockets.

### Hub: APNs without a library
- Endpoint: `https://api.push.apple.com` (prod/TestFlight) via `http2.connect`. Keep the session open and reuse; reconnect on `close`/`goaway`.
- JWT: header `{alg:"ES256", kid:<KEYID>}`, claims `{iss:<TEAMID>, iat}`. Sign with `crypto.sign('sha256', data, {key: p8Pem, dsaEncoding: 'ieee-p1363'})` (the `ieee-p1363` option is required; default DER is rejected by Apple). Cache token ~20-50 min (Apple rejects tokens older than 60 min and also rejects refreshing more than once per 20 min).
- Request headers: `:method POST`, `:path /3/device/<token>`, `apns-topic: <bundle id>`, `apns-push-type: alert`, `authorization: bearer <jwt>`. Payload `{aps:{alert:{title,body},sound:"default","thread-id":<sessionId>}, sessionId}` for deep-link.
- TestFlight builds use the **production** APNs host, not sandbox. (Debug builds installed from Xcode use sandbox. The app needs to know which; simplest is to send the build-environment flag with the device token registration, or just try prod and treat 400 BadDeviceToken as "try sandbox".)
- Handle `410 Unregistered` -> delete token (matches spec). Retry once on 5xx / connection error.
- Confidence: HIGH on mechanism (Apple "Establishing a token-based connection to APNs"); MEDIUM that nothing changed in 2026, re-verify the 20-min refresh rule at implementation.

### Hub: Tailscale whois
- On each request (cache per remote IP for ~60s): `execFile('tailscale', ['whois','--json', remoteAddress])`, parse `UserProfile.LoginName` and compare to configured owner; reject if exit non-zero. Binary path on Windows is `C:\Program Files\Tailscale\tailscale.exe`, which may not be on PATH for a Task Scheduler launch, so use the absolute path.
- Bind: `server.listen(port, <tailscale 100.x IP>)`, not `0.0.0.0`. Get the IP from `tailscale ip -4` at startup. If Tailscale is not up yet at login, retry with backoff (see Pitfalls for the boot-order issue).
- Hooks come from loopback: hub needs a second listener on `127.0.0.1` (or the same server bound to both) that skips whois but requires a local shared secret in the hook command. Do not expose the hook route on the tailnet listener.
- Alternative (not chosen): Tailscale LocalAPI over the Windows named pipe. Faster, but the pipe/auth details on Windows are poorly documented and `node:net` pipe quirks add risk. CLI call is fine at this request rate. Confidence MEDIUM, validate `whois --json` field names on the actual PC.
- Rationale for bearer token on top: whois proves *which device*, token proves *which paired app install*. Generate with `crypto.randomBytes(32)`, store only a SHA-256 hash, compare with `crypto.timingSafeEqual`.

### Hub: running at Windows login
| Choice | Why |
|---|---|
| **Task Scheduler**, trigger "At log on" for the user, action `node.exe C:\...\hub.js`, "Run only when user is logged on", restart-on-failure (every 1 min, up to 999 times), no execution time limit | Matches the spec. The hub must run as the interactive user so it sees `%USERPROFILE%\.claude` (transcripts, hooks settings, Claude auth) and the user's PATH. A Windows Service (node-windows 1.0.0-beta.8, NSSM) runs in session 0 as another account by default and breaks all of that. |
| Register with `schtasks /create /xml` or `Register-ScheduledTask` in a single `install.ps1` | One file, idempotent. |
| Hide the console window: launch via `wscript` VBS shim or `powershell -WindowStyle Hidden`, or set the task to "Run whether user is logged on or not" only if you store the password (do not) | Task Scheduler launching `node.exe` directly shows a console. Hidden launch is cosmetic. |
Confidence: HIGH on the service-vs-task reasoning (session-0 isolation and profile paths are well established), MEDIUM on exact flags.

### Hub: Claude Code integration points
| Item | Approach | Confidence |
|---|---|---|
| Spawn | `pty.spawn('claude.exe' or 'claude.cmd', args, {name:'xterm-256color', cols, rows, cwd, useConpty:true, env})`. Resolve the real path of the native install first. node-pty on Windows cannot spawn a `.cmd` shim reliably without `cmd.exe /c`; prefer the `claude.exe`. | MEDIUM, verify on the PC |
| Resume | `claude --resume <session-id>` | HIGH (per spec/Even Terminal) |
| Transcripts | `%USERPROFILE%\.claude\projects\<encoded-cwd>\<session-id>.jsonl`. Watch the directory tree (`fs.watch(dir,{recursive:true})` works on Windows) plus a startup scan. Parse line-by-line; treat unknown record types as skip, schema is undocumented/unstable. | MEDIUM |
| Hooks | Write `Stop` and `Notification` entries into `%USERPROFILE%\.claude\settings.json` (merge, never overwrite, back up first). Command hook: `curl.exe -s -X POST http://127.0.0.1:<port>/hook -H "x-echo-secret: ..." --data-binary @-` (hook JSON arrives on stdin; includes `session_id`, `transcript_path`). `curl.exe` ships with Windows 10 1803+. Claude Code may also offer an HTTP-type hook; verify in current hooks docs before choosing, since it would remove the curl dependency. | MEDIUM (command hooks), LOW (HTTP hook type) |

### iOS app
| Technology | Version | Purpose | Why | Confidence |
|---|---|---|---|---|
| Swift / SwiftUI | Xcode current (Swift 6.x), deployment target iOS 17 (or 18 if the shared DesignSystem already requires it; match WorkoutCoach) | UI | Required by project. `@Observable` and modern navigation need 17+. | HIGH |
| SwiftTerm | 1.99.3 (SPM, `https://github.com/migueldeicaza/SwiftTerm`) | Terminal view | The only serious Swift terminal emulator with a ready UIKit `TerminalView`. Wrap with `UIViewRepresentable`; use `feed(byteArray:)` for incoming bytes, `TerminalViewDelegate.send(source:data:)` for keystrokes, `sizeChanged` -> send resize to hub. Pin with `upToNextMinor` since a 1.99.x tag implies rapid churn; confirm the exact version resolves in Xcode. | HIGH (exists), MEDIUM (version/tag semantics, verify) |
| `URLSessionWebSocketTask` | system | WebSocket client | Native, supports binary + text frames, works over `wss://` and plain `ws://`. Covers everything needed. Do NOT add Starscream or Socket.IO. Write ~60 lines: connect, `receive()` loop, send, ping every 20s, exponential backoff reconnect with `since=<lastSeq>`. | HIGH |
| Keychain (`Security` framework, `SecItemAdd`/`SecItemCopyMatching`, `kSecAttrAccessibleAfterFirstUnlock`) | system | Store bearer token | ~25-line helper. No KeychainAccess/SwiftKeychainWrapper. `AfterFirstUnlock` so background push handling can still read it. | HIGH |
| APNs client side | system (`UIApplicationDelegateAdaptor`, `UNUserNotificationCenter`) | Push registration, deep link | `registerForRemoteNotifications()` -> hex token -> `POST /devices`. `userNotificationCenter(_:didReceive:)` reads `sessionId` and routes. Needs a small `AppDelegate` even in a SwiftUI app. Capability: Push Notifications entitlement `aps-environment`. | HIGH |
| `Codable` + `JSONDecoder` | system | Frame/message decoding | Plain; unit-test stream decoding and seq logic per spec. | HIGH |
| XcodeGen | 2.46.0 (brew installed locally is 2.44.1; `brew upgrade xcodegen`) | `project.yml` -> xcodeproj | Per constraints. Declare SPM package for SwiftTerm in `project.yml` `packages:`; entitlements and `INFOPLIST_KEY_*` in `settings`. Reference shared DesignSystem via `sources:` path or a local SPM package (decide in architecture; avoid copying). | HIGH |
| TestFlight | via `xcodebuild archive` + `xcodebuild -exportArchive` + `xcrun altool`/`xcrun notarytool` not needed; upload with `xcodebuild -exportArchive` using `destination: upload` in ExportOptions.plist, or Xcode Organizer for the first build | Distribution | Paid account in hand. Automatic signing with `DEVELOPMENT_TEAM` set in `project.yml`. Keep a 5-line `release.sh`. No fastlane. | MEDIUM |
| Network permissions | `NSLocalNetworkUsageDescription` not needed (Tailscale 100.x is not LAN Bonjour); ATS: if using `ws://` to a 100.x IP, add an ATS exception for that. Prefer one of: (a) `wss` via `tailscale cert`/`tailscale serve` on the hub for a real MagicDNS HTTPS name, no ATS exception; (b) plain `ws://` over the WireGuard tunnel with ATS `NSAllowsLocalNetworking`/per-domain exception. | See below | MEDIUM |

**TLS decision (open):** Traffic is already WireGuard-encrypted by Tailscale, so plain `http/ws` to the 100.x address is acceptable for a personal tool, at the cost of an ATS exception (`NSAllowsArbitraryLoads` is flagged in App Review but TestFlight internal testing is not reviewed that strictly; per-domain exceptions for an IP are awkward because ATS exceptions are domain-based). The cleaner option is MagicDNS name + `tailscale cert` (Let's Encrypt for `*.ts.net`), which gives real `wss://` with zero ATS changes. Cost: hub loads the cert files and must renew them (cert is 90-day; `tailscale cert` can be re-run at hub start). Recommend **start with wss via tailscale cert**; fall back to ATS exception only if cert plumbing proves painful. Confidence MEDIUM, needs a spike.

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|---|---|---|---|
| PTY | node-pty 1.1.0 | `@lydell/node-pty` fork, Bun/Deno PTY, Windows `CreatePseudoConsole` via FFI | Fork adds trust surface; official package has prebuilds and Microsoft maintenance |
| WS server | ws | `uWebSockets.js`, Socket.IO, built-in WebSocket (client only) | Overkill / no server API / extra protocol layer |
| HTTP | node:http | Express, Fastify, Hono | 5 routes; framework is pure overhead |
| APNs | node:http2 + crypto | `@parse/node-apn` 8.2.0, `apns2`, Firebase | Extra deps for ~60 lines; Firebase adds a Google dependency for nothing |
| Persistence | JSON file | `better-sqlite3`, `node:sqlite` | Native addon pain on Windows / not needed at this scale |
| File watching | `fs.watch` + offsets | chokidar 6 | One recursive watch on one dir tree suffices |
| Autostart | Task Scheduler | node-windows (beta), NSSM, pm2 | Session-0/profile problems; pm2 adds a daemon |
| iOS WS | URLSessionWebSocketTask | Starscream, SwiftNIO, Network.framework `NWConnection` WS | Native task is sufficient and supports background-free usage here |
| iOS terminal | SwiftTerm | WKWebView + xterm.js | Native view, better keyboard/gesture behavior and no JS bundle; xterm.js only if SwiftTerm rendering of Claude's TUI is unacceptable (spike early) |
| Push relay | Direct APNs from hub | Third-party push service | Hub can reach Apple directly; fewer parties |
| Xcode project | XcodeGen | Tuist, hand-managed pbxproj | Mandated; simplest |
| Build/release | shell + xcodebuild | fastlane | Single app, single lane |

## Installation

```bash
# Hub (on the PC, in the hub repo)
# Node 24 LTS via winget: winget install OpenJS.NodeJS.LTS
# node-pty compiles from source if no prebuild matches; have "Desktop development with C++" + Python ready as a fallback
npm install node-pty@1.1.0 ws@8.22.2

# iOS (on the Mac)
brew install xcodegen          # or: brew upgrade xcodegen -> 2.46.0
xcodegen generate
# SwiftTerm is resolved by Xcode/SwiftPM from project.yml `packages:`
```

No dev dependencies. Tests: `node --test`.

## What NOT to use
- Windows Service wrappers (node-windows, NSSM): wrong user/session, cannot see the Claude profile.
- WSL/tmux: the PC has neither; ConPTY via node-pty is the path.
- Express, Socket.IO, chokidar, dotenv, uuid (`crypto.randomUUID()`), axios (`fetch` is global in Node 24), jsonwebtoken/jose for APNs (`crypto.sign` suffices), better-sqlite3.
- Starscream, KeychainAccess, Alamofire, TCA, fastlane in the app.
- Parsing the terminal byte stream to derive chat messages: use the transcript JSONL for chat, PTY only for the terminal view.

## Sources
- npm registry (`npm view`) for node-pty 1.1.0, ws 8.22.2, @parse/node-apn 8.2.0, chokidar 6.0.0, better-sqlite3 13.1.1, node-windows 1.0.0-beta.8: 2026-11-11 (HIGH)
- https://nodejs.org/dist/index.json: Node 24.22.3 Krypton LTS, 26.13.1 Lithium LTS (HIGH)
- https://github.com/microsoft/node-pty README: Windows 10 1809+ requirement, winpty removed (HIGH)
- GitHub releases API: SwiftTerm v1.99.3, XcodeGen 2.46.0 (HIGH for existence)
- Apple docs "Establishing a token-based connection to APNs" and "Sending notification requests to APNs" (from knowledge; not re-fetched this session, MEDIUM)
- Tailscale `whois` CLI docs (from knowledge, MEDIUM; verify JSON fields on the PC)
- Claude Code hooks documentation (from knowledge, not re-fetched; verify hook stdin schema and any HTTP hook type, MEDIUM/LOW)
