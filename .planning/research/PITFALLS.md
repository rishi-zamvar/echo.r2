# Domain Pitfalls

**Domain:** Phone (iOS) to Windows PC hub controlling Claude Code CLI sessions over Tailscale
**Researched:** 2026-11-11
**Overall confidence:** MEDIUM. Most items come from well-known platform behavior (training knowledge) and were NOT re-verified against live docs in this pass. Items marked [verify] should be confirmed in the phase that touches them. Claude transcript and hook internals change between versions, so verify against the installed CLI version.

Suggested phase labels used below (map to roadmap as needed):
P1 Hub skeleton (service, auth, Tailscale), P2 PTY sessions, P3 Transcript/chat, P4 Hooks + APNs, P5 iOS app (list, chat, terminal), P6 Resilience/reconnect, P7 Release/ops (TestFlight, deploy, doctor).

---

## Critical Pitfalls

### 1. PTY child process tree survives kill, leading to orphaned `claude` and two writers
**What goes wrong:** `pty.kill()` on Windows ends the ConPTY host/shell but not necessarily grandchildren (`claude.exe` spawns node/git-bash/MCP servers/subagents). After a hub restart or "stop session", an orphan `claude` keeps running and still appends to the same transcript. "Resume" then starts a second writer on the same session.
**Why:** ConPTY has no POSIX process groups. node-pty kill semantics differ on Windows (known hangs/"AttachConsole failed" noise on exit).
**Prevention:** Kill with `taskkill /PID <pid> /T /F`. Put each session in a Windows Job Object if feasible (or at minimum track PIDs in the store). On hub boot, sweep for stale `claude` PIDs recorded in the store and kill them BEFORE offering resume. Add a test: spawn, kill, assert no child remains.
**Warning signs:** Task Manager shows `claude.exe`/`node.exe` after stopping a session; transcript grows while session is "stopped"; duplicate notifications.
**Phase:** P2 (kill) and P6 (boot sweep).

### 2. node-pty native build / ABI breakage on Windows
**What goes wrong:** `npm install` on the PC fails (needs Python, VS Build Tools with C++ workload, Spectre-mitigated libs for some versions) or works once and breaks after a Node upgrade (ABI mismatch, "module was compiled against a different Node version"). The service then silently fails at login.
**Prevention:** Prefer a build that ships Windows prebuilds (check `@lydell/node-pty` or current `node-pty` release notes [verify]) so no toolchain is needed. Pin Node version (`.nvmrc`/`engines`, and the scheduled task points to an absolute node.exe path, not PATH). Commit lockfile. Add a startup self-test that spawns `cmd /c echo ok` through node-pty and logs failure loudly. Document toolchain install in the runbook if prebuilds are unavailable.
**Warning signs:** Hub starts but `POST /sessions` 500s; works in terminal but not in the scheduled task (different PATH).
**Phase:** P1/P2.

### 3. Spawning `claude` via node-pty: wrong executable, wrong env, Git Bash requirement
**What goes wrong:** `claude` may resolve to `claude.exe`, a `.cmd` shim, or an npm global shim. node-pty cannot exec `.cmd` directly (needs `cmd.exe /c`). Under a Task Scheduler context PATH differs, so `claude` is not found. Claude Code on Windows also needs Git for Windows (bash); if it cannot find it, it errors at start (`CLAUDE_CODE_GIT_BASH_PATH`) [verify].
**Prevention:** Resolve an absolute `claude` path at install time (`where claude`) and store it in hub config. Pass explicit env: `USERPROFILE`, `HOME`, `APPDATA`, `LOCALAPPDATA`, `PATH`, `CLAUDE_CODE_GIT_BASH_PATH`, `TERM=xterm-256color`. Smoke test `claude --version` from the same launch context as the task.
**Phase:** P2.

### 4. Raw-byte scrollback replay produces garbage (torn escape sequences, torn UTF-8, ConPTY redraw noise)
**What goes wrong:** Spec says "bounded raw-output ring buffer for replay". Trimming the ring at an arbitrary byte cuts mid ANSI escape or mid UTF-8 character, and replaying from the middle of an Ink (Claude's TUI) redraw gives a corrupted screen. ConPTY also re-renders from its own screen buffer, so the stream is not a faithful log, and cursor-position redraws depend on prior state.
**Prevention:** Run `@xterm/headless` + serialize addon on the hub per session (cheap, same parser as the terminal model). On (re)connect send a serialized screen snapshot, then live bytes from seq N. Keep the ring only for short gap-fill, and cut it on chunk boundaries (store chunks, not a byte array). Decode with `StringDecoder`/keep bytes as Uint8Array end-to-end; never `toString()` per chunk.
**Warning signs:** Terminal view shows overlapping boxes/stray `[0m` after reconnect; �� characters at chunk seams.
**Phase:** P2 (hub snapshot), P6 (replay by seq).

### 5. PTY has exactly one size, but multiple clients/views fight over it
**What goes wrong:** Phone terminal is ~50 cols; PC/Even Terminal/glasses expect wider. Every phone `resize` reflows Claude's TUI for all consumers and the transcript-less terminal history. Resize to 0 cols/rows (SwiftTerm before layout) throws or wedges ConPTY. Resize storms during keyboard show/hide and rotation.
**Prevention:** Decide an owner policy: hub spawns at fixed 120x30; only the Terminal view sends resize, debounced (~250 ms), clamped (min 20x5), and ignored when chat view is active. Resize before first output when possible. Validate numbers server-side.
**Phase:** P2/P5.

### 6. Hub not running after reboot, or running but invisible/blocked (Task Scheduler context)
**What goes wrong:**
- "At log on" trigger only fires after interactive login. A Windows Update reboot while Rishi is in California and not logged in leaves the hub dead until someone logs in.
- "Run whether user is logged on or not" removes the interactive session: no profile/HKCU surprises are rare, but Claude auth (`~/.claude` credentials under the user profile) still works only if the task runs as that same user with password stored; ConPTY generally works but unverified in session 0 [verify].
- Defaults kill it: "Stop the task if it runs longer than 3 days", "Start only if on AC power", "Stop if switching to battery", "do not start a new instance" with no restart-on-failure.
- A node.exe launched by the task shows a console window, which closes if the user closes it.
- Pairing code "printed to console" has nowhere to print when hidden.
**Prevention:** Use Task Scheduler (not a Windows service: services run as LocalSystem by default, no user profile or Claude login, and node-pty/ConPTY under services is painful). Configure: trigger At log on AND At startup (with delay), run as the user, "Run whether logged on or not" only after verifying Claude works there, disable the 72h stop and power conditions, restart every 1 min up to 999 times on failure, `MultipleInstances = IgnoreNew`. Enable Windows auto-logon (or accept it) so unattended reboot recovers [decision for Rishi, security tradeoff]. Launch hidden (`pwsh -WindowStyle Hidden` or `wscript` shim). Install via a scripted `install-task.ps1` (XML export), not by hand. Pairing code goes to a file + `hub pair` CLI that talks to loopback, never stdout only. Log to a rotating file.
**Warning signs:** App shows offline after a night; no hub process after reboot; task "Last Run Result" non-zero.
**Phase:** P1 (install script) and P7 (runbook).

### 7. Tailscale binding and whois on Windows
**What goes wrong:**
- Hub starts before the Tailscale interface has an IP, so `listen(100.91.236.115)` throws `EADDRNOTAVAIL` and the process exits. (Tailscale is a service and usually up before login, but not guaranteed; IP can change on re-auth.)
- Windows Firewall: the Tailscale adapter is often classified Public, and inbound node.exe is blocked by default. Works locally, times out from phone.
- LocalAPI on Windows is a named pipe, not a unix socket; naive HTTP-over-socket code written on Mac fails. Simplest reliable approach is spawning `tailscale whois --json <ip>` (cost: process spawn per request, so cache per IP for ~60 s).
- Whois returns `UserProfile` for user-owned devices but only `Tags` for tagged nodes. A check like `UserProfile.LoginName === me` rejects a tagged phone, or wrongly accepts shared-in nodes.
- Falling back to `0.0.0.0` "to make it work" silently exposes the hub on LAN/other interfaces.
- Exit-node/DNS: iOS app must have Tailscale VPN connected; if Tailscale is off, connection errors look like hub downtime.
**Prevention:** Resolve the IP at startup via `tailscale ip -4` and retry-bind with backoff (never fall back to 0.0.0.0). Add a one-time scripted firewall rule scoped to the Tailscale interface/`100.64.0.0/10` and the hub port. Pin the expected whois login (and/or node id of the phone) in config and fail closed on lookup errors. Also add a Tailscale ACL restricting phone to PC:port. Hook receiver listens on 127.0.0.1 only, on a different port, and is not subject to whois (see pitfall 15). In the app, show "Tailscale not connected?" hint on connect failure.
**Phase:** P1.

### 8. iOS background WebSocket limits and half-open sockets
**What goes wrong:** iOS suspends the app (and kills its sockets) within seconds of backgrounding; there is no supported way to hold a WebSocket for a normal app. Devs try keep-alive tricks, background modes abuse (audio/VoIP) and get App Review/TestFlight rejection or battery drain. Separately, switching Wi-Fi/LTE/Tailscale toggles leaves half-open sockets that look alive for minutes.
**Prevention:** Treat background as disconnected by design. Push (APNs) is the background channel; foreground reconnect always sends `since=<lastSeq>`. Use app-level ping/pong (e.g., 15 s ping, 10 s pong timeout) rather than relying on TCP. Observe `NWPathMonitor` + scene phase to proactively reconnect. Reconnect with capped exponential backoff plus jitter. Make the server idempotent for replay (seq gaps detectable; if `since` older than ring, send snapshot).
**Warning signs:** Terminal "frozen" after unlocking the phone; duplicate lines after reconnect (dedupe by seq).
**Phase:** P5/P6.

### 9. APNs: token auth details and sandbox vs production mismatch
**What goes wrong:**
- Device tokens differ per environment. A build run from Xcode (debug) registers a sandbox token; a TestFlight/App Store build registers a production token. Sending a sandbox token to the production host (or vice versa) returns `BadDeviceToken`, which a naive "delete token on error" handler turns into silently lost pairing.
- JWT provider token: must be refreshed at least every 60 min but not more often than every ~20 min (`TooManyProviderTokenUpdates` 429 / `ExpiredProviderToken` 403). Regenerating per push is a classic bug.
- APNs requires HTTP/2 (use Node `http2`, not `fetch`/`https`), headers `apns-topic` = bundle id, `apns-push-type: alert`, `apns-priority`.
- `.p8` is downloadable once; losing it means revoking and recreating the key. Key ID + Team ID must be kept with it.
- Payload limit 4 KB; hook-derived summaries can be long.
- Notification permission denied or Focus mode hides alerts; "Time Sensitive" needs a capability.
**Prevention:** Store `{token, environment}` per device (app sends `#if DEBUG sandbox else production`, or reads the `aps-environment` entitlement) and route to `api.sandbox.push.apple.com` vs `api.push.apple.com` accordingly. Cache the JWT ~45 min. Only delete tokens on `410 Unregistered`; log other reasons verbatim. Back up the `.p8` + IDs in a password manager. Truncate bodies (~120 chars). Use `apns-collapse-id` = session id so repeated Stop events replace each other. Add a hub `POST /test-push` plus an app "Send test notification" in Settings.
**Warning signs:** Pushes work in debug builds and not TestFlight (or reverse); everything works for an hour then 403s.
**Phase:** P4, verified again in P7 on a real TestFlight build.

### 10. Two writers on one Claude session
**What goes wrong:** Interleaved JSONL appends and corrupted conversation state when (a) hub resumes a session while Even Terminal/plain-terminal `claude` still has it open, (b) orphan process (pitfall 1), (c) two phone clients, or chat input + terminal keystrokes in the same PTY collide (half-typed line plus injected message). Also `--resume` may write to a NEW session id/file rather than the original in some versions, so the tailer follows the wrong file [verify with installed CLI].
**Prevention:** Hub-owned sessions: assign the id up front with `claude --session-id <uuid>` so PTY-to-transcript mapping is exact and not guessed by cwd/mtime. Single input lock: input accepted from one client at a time (last-active wins with a visible "controlled by other device" state); chat-view "send" must refuse when the terminal has unsent text or Claude is mid-permission-prompt (state from hook/transcript), or simply inject text then CR atomically in one PTY write. Take-over guard: before spawning resume, refuse if the transcript mtime is within ~30 s or a `claude` process holding that session id exists (scan with `wmic`/PowerShell `Get-CimInstance Win32_Process` command lines), then require explicit confirmation. Keep external sessions strictly read-only in the data model (no input endpoint at all).
**Phase:** P2 (lock + session-id), P3 (external watch), P6 (take-over guard).

### 11. Tailing JSONL while it is being written
**What goes wrong:** Reading a chunk ending mid-line gives `JSON.parse` errors or, worse, a silently dropped half event; multi-byte UTF-8 split across reads; `fs.watch` on Windows emits duplicate/coalesced/missed events and may not fire for appends on some filesystems; file rotation/truncation or a new file on resume; tailer re-reads everything after restart and re-notifies; huge transcripts (tens of MB) parsed on every connection.
**Prevention:** Track a byte offset per file; read `Buffer` from offset, split on `0x0A`, keep the trailing fragment unparsed until its newline arrives (persist offset only up to last complete newline). Decode per full line. Use `fs.watch` as a hint plus a 500-1000 ms stat-poll fallback. Handle size < offset (truncate) by resetting. Wrap each line parse in try/catch and skip+log. On first attach, index to current end and serve history by paging backward, not full parse. Tolerant schema: ignore unknown `type`s, treat fields as optional, tag `isSidechain` (subagent) messages and collapse them, handle tool_result entries that appear as user-role messages. Project dir naming is lossy (path separators and punctuation to `-`, e.g. `C:\a\b` becomes `C--a-b`): never reverse-map to cwd; read `cwd` from entries or the hook payload instead. Keep a recorded fixture transcript from the installed CLI version as a parser test; run it after every Claude Code update.
**Warning signs:** Missing assistant messages, occasional "Unexpected end of JSON", chat showing gaps that fill after reopening.
**Phase:** P3.

### 12. Claude Code hooks: per-turn, per-subagent, per-process firing; blocking; settings clobbering
**What goes wrong:**
- `Stop` fires at the end of EVERY assistant turn, not "session finished". Rapid conversations or auto-continue flows spam pushes. `SubagentStop` is separate for subagents [verify], and any nested `claude -p` or Even Terminal/other session on the PC fires the same user-level hook, so the hub gets events for sessions it does not own.
- `Notification` fires for permission prompts and for idle ("waiting for input") and can duplicate next to `Stop`.
- Hook commands run synchronously and a slow/hanging hook (hub down, curl missing in Windows shell, wrong quoting under Git Bash vs cmd) stalls or errors Claude's turn. Windows quoting of JSON/paths in `settings.json` commands is fragile.
- Hooks are snapshotted at session start; already-running sessions do not see newly installed hooks, so "pushes don't work" for those.
- Programmatic edit of `~/.claude/settings.json` can clobber the user's other hooks/permissions or race with Claude writing the file.
- Anyone local can POST fake events to loopback.
**Prevention:** Hook command = tiny Node script (absolute node path, no shell quoting games) that reads stdin JSON (`session_id`, `transcript_path`, `cwd`, `hook_event_name`), POSTs to `127.0.0.1` with a short timeout (~2 s), a shared-secret header, always exits 0, and swallows errors. Hub dedupes/debounces per `session_id` (e.g., coalesce Stop within 5-10 s, ignore if `stop_hook_active`), maps `session_id` to known sessions and treats unknown ones as "external" (notify only if user opted in). Distinguish state: Stop = "done/idle", Notification(permission) = "needs you". Install hooks by JSON-merge (read, add entries tagged with a marker, write atomically, keep a backup), with an `uninstall`. Prefer a hub-level fallback signal too: transcript quiet for N seconds after last assistant message. Note in UI that already-open sessions need restart for hooks.
**Phase:** P4.

### 13. Auth and pairing weaknesses (this app is remote code execution by design)
**What goes wrong:** Whoever holds a valid token can run `claude` in any cwd, i.e., arbitrary code on the PC. Common mistakes: short or reusable pairing code; no expiry/rate-limit; code shown in logs; token stored plaintext on hub; bearer token in WebSocket query string (ends up in logs); non-constant-time compare; whois treated as sufficient or as optional; no revocation; iOS Keychain item survives app delete/reinstall (stale token, user stuck at 401 loop) or is stored with an accessibility class that blocks background/after-reboot use; arbitrary `cwd`/path traversal in `POST /sessions`; transcripts/pushes leaking content on the lock screen (discreet app!).
**Prevention:** Pairing code: 8+ chars from CSPRNG (or 128-bit via QR), single use, 5 min expiry, 5 attempts then lock, generated only via local `hub pair` command. Token: 256-bit random, store only SHA-256 on hub with device name and last-seen, compare with `crypto.timingSafeEqual`. Send token in `Authorization` header (URLRequest for `URLSessionWebSocketTask` supports headers), never in URL. Auth is whois AND token, fail closed. Add `GET /devices` + revoke, and a "revoke all" CLI. Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; on 401 clear and return to pairing. Restrict `cwd` to an allowlist/root list (e.g., configured project roots) and `realpath` it. Don't pass `--dangerously-skip-permissions` by default. Push bodies generic for lock screen unless user opts in ("Session X needs you"). Never log transcript content or tokens.
**Phase:** P1 (auth), P4 (push content), P5 (Keychain).

### 14. WSS on a tailnet: certs and iOS App Transport Security
**What goes wrong:** Spec says WSS, but a hub on `100.x` has no valid cert. ATS blocks `ws://` to non-exempt hosts, and `NSAllowsLocalNetworking` does not cover `100.64/10`. Devs then blanket-disable ATS (App Review concern, also unneeded complexity) or hand-roll cert pinning. If using `tailscale cert` (MagicDNS name, requires HTTPS enabled in the tailnet), certs expire in ~90 days and the renewal job is yet another thing that rots.
**Prevention:** Decide explicitly in P1. Simplest: plain `ws://` with a scoped `NSExceptionDomains` entry for the tailnet hostname (traffic is already WireGuard-encrypted end-to-end), no cert code. If WSS is wanted, use Tailscale-issued cert via MagicDNS and automate renewal at hub start (check expiry on boot and daily). Document the choice (the spec's "WSS" can be softened).
**Phase:** P1/P5.

### 15. Hook receiver and hub on same trust surface
**What goes wrong:** Putting the hook endpoint on the tailnet listener exposes it to the phone (and whois fails for loopback, so devs weaken the check); or binding it to `0.0.0.0`.
**Prevention:** Separate listener on `127.0.0.1` with shared secret; the secret generated at install and embedded in the hook script config.
**Phase:** P1/P4.

---

## Moderate Pitfalls

### 16. SwiftTerm performance with large output and scrollback
**What goes wrong:** Feeding every WebSocket message to the terminal on the main thread during a burst (Claude dumping a diff, replaying a 1 MB snapshot) freezes the UI; very large scrollback inflates memory (iOS may jetsam the app); per-frame redraws during selection/scroll. Soft keyboard lacks Esc/Ctrl/Tab/arrows, making Claude's TUI unusable without an accessory bar. Terminal fonts/dynamic type changes trigger resize spam (pitfall 5).
**Prevention:** Cap scrollback (a few thousand lines, set explicitly rather than default), coalesce incoming chunks and feed once per frame/16-50 ms, feed in bounded slices when replaying snapshot, never block the main actor on decode. Send snapshot (not full history) on connect so phone never parses megabytes. Provide an input accessory row (Esc, Tab, Ctrl-C, arrows). Profile with a synthetic 5 MB burst early.
**Phase:** P5.

### 17. Encoding and line-ending issues
**What goes wrong:** Windows console code pages (cp437/1252) vs UTF-8; ConPTY emits UTF-8 VT but child tools may not; Enter must be `\r` (not `\n`) into ConPTY; bracketed paste for multi-line chat input; emoji/CJK width mismatches between xterm model and SwiftTerm.
**Prevention:** Set `chcp 65001`-equivalent env/`PYTHONUTF8`/`LANG` hints where relevant; chat "send" = text via bracketed paste (`ESC[200~ ... ESC[201~`) then `\r`; test with multi-line, emoji, and Windows paths.
**Phase:** P2.

### 18. WebSocket protocol design gaps
**What goes wrong:** seq is per-session but not monotonic across hub restarts; ring buffer evicted past client's `since` and client has no signal; no backpressure for slow phone (hub memory grows); chat and term streams share one connection without framing.
**Prevention:** Persist an epoch/boot id with seq; server replies `{type:"reset", snapshot}` when `since` is not replayable; per-socket send buffer limit (drop and force resync); define versioned message envelope now (`v`, `type`, `seq`).
**Phase:** P6 (design the envelope in P1/P2).

### 19. Session state heuristics (running / waiting / done)
**What goes wrong:** Inferring state from PTY output or transcript timing flaps (Claude "thinking" quietly looks idle).
**Prevention:** Derive from explicit signals: process alive (PTY), hooks (Stop/Notification), last transcript event type; hysteresis (state changes only after a debounce). Keep the state machine in one place with a unit test.
**Phase:** P3/P4.

### 20. Persistence and concurrent store writes
**What goes wrong:** JSON file corrupted by crash mid-write; two handlers racing.
**Prevention:** Atomic write (write temp + rename) or use Node's built-in `node:sqlite` if available in the pinned Node [verify]; a single module owns the store.
**Phase:** P1.

### 21. Disk and log growth, memory leaks in long-lived hub
**What goes wrong:** Logs and snapshots grow unbounded on an always-on PC; headless terminals per dead session never disposed.
**Prevention:** Rotating logs (size-capped), dispose per-session objects on exit, `/health` reports memory and session counts.
**Phase:** P7.

---

## Minor Pitfalls

### 22. XcodeGen and signing friction
**What goes wrong:** pbxproj gitignored means entitlements (push, Keychain), bundle id, and capabilities must live in `project.yml`; missing `aps-environment` entitlement is a silent "no token". Shared DesignSystem copied from other repos drifts.
**Prevention:** Declare entitlements in `project.yml`; reference DesignSystem as a local Swift package or a pinned copy with a recorded source commit; build in CI-like script before each TestFlight.
**Phase:** P5/P7.

### 23. Deep link on notification tap
**What goes wrong:** Cold-start tap handling differs from foreground; session id unknown after hub reset.
**Prevention:** Put `sessionId` in payload `userInfo`; handle `didReceive response`, navigate after connection ready, show "session not found" gracefully.
**Phase:** P4/P5.

---

## Why personal tools rot (ZeeChat lesson) and prevention

Note: the actual cause of ZeeChat's demise is not in the provided files; the list below is the general pattern for solo infra projects plus facts specific to this stack. LOW confidence on "why ZeeChat died", HIGH confidence on the expiry facts. Worth asking Rishi (or reading `legacy-reference/`) for the real cause.

| Rot source | Specific to echo.r2 | Prevention |
|-----------|---------------------|------------|
| TestFlight builds expire after 90 days | App silently stops launching on the phone | Calendar reminder at day 60; scripted `archive + upload` (fastlane or a shell script) so rebuilding is one command; keep Apple Developer renewal on autopay |
| Tailscale node key expiry (default ~180 days) | `zee-cloud` drops off tailnet and hub unreachable | Disable key expiry for the PC in the Tailscale admin console; note it in the runbook |
| Deploy drift (PC runs code not in git / not the version the app expects) | Hub edited by hand, or updated by Dispatch "swe" ad hoc | Single idempotent `deploy.ps1` (`git pull`, `npm ci`, restart task, run `doctor`); `GET /health` returns git SHA + protocol version; app shows a banner on protocol mismatch |
| Dependency and platform churn | Claude Code updates change transcript/hook format; Node update breaks node-pty; Windows Update reboots | Pin Node; fixture-based parser test using a recorded transcript; `doctor` command prints Claude version vs last-tested version and warns; tolerate unknown fields |
| Silent failure (no one notices hub is dead) | Task stopped, Tailscale off, APNs key revoked | Hub sends a "hub started" push on boot; external dead-man check optional (e.g., the Mac's Dispatch daemon pinging `/health` and messaging on failure); in-app Settings shows hub version, uptime, last hook received, last push result |
| Operational knowledge lives in head | Pairing, firewall rule, task config, `.p8` | Short `RUNBOOK.md` plus `install.ps1` that does task + firewall + hooks; secrets inventory (`.p8`, Key ID, Team ID, bundle id) in password manager |
| Scope creep before v1 is dependable | v2 handoff/glasses work starts before basics are solid | Hold the roadmap: v1 done when reconnect + push are reliable for 2 weeks of real use |
| Cert/token expiry | Tailscale certs (if WSS) 90 days | Avoid certs (pitfall 14) or auto-renew |

**Phase:** P7 (ops hardening) but start `/health`, version and `doctor` in P1.

---

## Phase-Specific Warnings

| Phase topic | Likely pitfall | Mitigation |
|-------------|----------------|------------|
| P1 Hub + install | Task Scheduler context, bind-before-Tailscale, firewall, whois on tagged nodes, ATS/WSS decision | Install script, retry-bind, fail-closed whois, decide ws vs wss |
| P1 Auth/pairing | Weak code, token in URL, plaintext tokens | CLI-issued single-use code, hashed tokens, header auth |
| P2 PTY | node-pty build, claude path/env, tree kill, resize, encoding, snapshot-vs-ring | Prebuilds + pinned Node, absolute paths, taskkill /T, headless xterm snapshot |
| P3 Transcript | Partial lines, fs.watch, lossy dir names, schema drift | Offset+newline buffering, poll fallback, fixtures |
| P4 Hooks + APNs | Per-turn Stop spam, blocking hooks, sandbox/prod tokens, JWT refresh, HTTP/2 | Debounce, node hook script, env-tagged tokens, cached JWT, `http2` |
| P5 iOS | Background sockets, SwiftTerm main-thread load, Keychain class, missing key row | Scene-phase handling, batching, accessory bar |
| P6 Reconnect | Seq gaps, epoch after restart, backpressure | Reset+snapshot protocol, per-socket limits |
| P6 Take-over | Two writers | Liveness check + confirmation, orphan sweep |
| P7 Release/ops | 90-day TestFlight, Tailscale key expiry, deploy drift | Reminders, disable key expiry, `deploy.ps1`, `doctor`, health banner |

## Research flags
- Needs deeper phase research: P2 (node-pty distribution/prebuilds and Job Object kill on Windows; Claude `--session-id` and `--resume` file behavior), P3 (current transcript schema of installed CLI), P4 (current hook event list/payloads incl. SubagentStop and Notification types), P7 (TestFlight/fastlane automation).
- Standard patterns: P5 SwiftUI screens, APNs HTTP/2 sender once the two environment rules above are applied.

## Sources
- Platform knowledge (training data, unverified in this pass): node-pty/ConPTY behavior, Task Scheduler options, Tailscale whois/LocalAPI, iOS background execution, APNs provider token rules (JWT 20-60 min, sandbox/production tokens), TestFlight 90-day build expiry, Tailscale node key expiry default. Confidence MEDIUM.
- Project inputs: `/Users/rishizamvar/Documents/Projects/echo.r2/.planning/PROJECT.md`, `/Users/rishizamvar/Documents/Projects/echo.r2/docs/superpowers/specs/2026-11-11-echo-r2-v1-design.md`.
- To verify against official docs during phases: Claude Code hooks reference (code.claude.com docs), Apple "Establishing a token-based connection to APNs", Tailscale docs (whois, key expiry, `tailscale cert`), node-pty README/issues.
