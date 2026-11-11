# Project Research Summary

**Project:** echo.r2
**Domain:** Personal iPhone remote for Claude Code agents hosted on a Windows PC hub over Tailscale
**Researched:** 2026-11-11
**Confidence:** MEDIUM (versions + Claude transcript/hook formats verified; all Windows-specific behavior unverified from the Mac)

## Executive Summary

echo.r2 is a single-user remote control: one Node hub on the Windows PC owns every `claude` PTY (node-pty/ConPTY), tails Claude's transcript JSONL for chat, receives Claude hooks on loopback, sends APNs directly, and serves a tailnet-bound listener to a thin SwiftUI app (one WebSocket + small REST, SwiftTerm terminal). Wedge vs Claude Remote Control/Happy/Omnara: start sessions from the phone, sessions outlive the phone, no cloud relay, real terminal + chat.

Minimal approach: hub = 2 runtime npm deps (node-pty, ws) + Node stdlib (http, http2 APNs, crypto, fs tailing, node:test); app = 1 SPM dep (SwiftTerm). Design rules: hub session id == Claude session id (`claude --session-id <uuid>`); everything the phone sees is a seq-numbered event in one per-session ring; chat only from transcript, never PTY text; state from signals (PTY exit, hooks), never screen scraping.

Main risks are all on the PC: ConPTY/node-pty build+spawn, orphaned `claude` trees / two writers, hooks + Task Scheduler context, Tailscale bind/whois/firewall. Secondary: iOS background sockets (treat background as disconnected, push is the background channel) and APNs sandbox vs production tokens. Retire PC risks first with spikes; make the hub testable from a CLI client before any iOS UI.

## Reconciled Conflicts

| Topic | Conflict | Recommendation |
|---|---|---|
| Transport | STACK: `wss://` via `tailscale cert`/MagicDNS. PITFALLS: plain `ws://` + scoped ATS exception (WireGuard already encrypts). | **Plain `ws://` to MagicDNS name or 100.x IP, no cert code.** Add ATS exception only if device test needs it. Token in `Authorization` header, never URL. Revisit `tailscale cert` only if exception unworkable. **Spike on device early in iOS phase.** |
| Replay | Raw chunk ring + `reset` vs `@xterm/headless` snapshot. | **v1: chunk-boundary ring** (Uint8Array, coalesce 16–50 ms, never cut mid-chunk). On gap send `reset`; client clears, hub nudges resize to force TUI repaint. Adopt `@xterm/headless` only if spike shows corruption. Chat replays from transcript. |
| Hook mechanism | command+curl.exe vs `type:"http"` vs node script. | **`type:"http"` hook to 127.0.0.1.** Spike: confirm installed `claude --version` honors http hooks + can carry a secret. Fallback: command hook `node hook.js` by absolute path, exit 0, 2 s timeout. Separate loopback listener, validate payload, 200 immediately, debounce Stop per session. |
| Hook secret | none on loopback vs shared secret | Shared secret if supported; else validate shape + session_id. |
| Autostart | at-startup/auto-logon vs at-logon interactive | **Task Scheduler At log on, interactive user, restart on failure, no time limit, no power conditions, IgnoreNew.** No stored password. Auto-logon is Rishi's call. No Windows service. |
| Process kill | — | `taskkill /PID <pid> /T /F`, PIDs in store, sweep stale on boot. Job Objects only if leaks. |
| Terminal view | SwiftTerm vs xterm.js-in-WKWebView fallback | SwiftTerm; spike early with real Claude output. |

## Key Findings

### Recommended Stack

**Hub:** Node 24 LTS (pinned, absolute `node.exe` in task); node-pty 1.1.0 (spawn `claude.exe`, not `.cmd` shim); ws 8.22.2 on `node:http`; `node:http2` + `node:crypto` APNs (ES256, `dsaEncoding:'ieee-p1363'`, JWT cached ~45 min); JSON store with atomic rename; `fs.watch` + stat-poll fallback for transcripts; `execFile tailscale whois --json` (absolute path, cached ~60 s) + 256-bit per-device bearer token (SHA-256 at rest, `timingSafeEqual`); `node:test`.

**App:** SwiftUI iOS 17+; SwiftTerm 1.99.x (`upToNextMinor`) with extra-keys bar (Esc, Tab, Ctrl-C, arrows); `URLSessionWebSocketTask` (~60 lines, ping, backoff reconnect with `since=<lastSeq>`); hand-rolled Keychain helper (`AfterFirstUnlockThisDeviceOnly`); XcodeGen 2.46; shell `release.sh` for TestFlight.

**Avoid:** Express, Socket.IO, chokidar, native sqlite, jsonwebtoken, node-windows/NSSM/pm2, Starscream, KeychainAccess, fastlane, PTY-byte parsing for chat.

### Expected Features

**Table stakes:** pairing (CLI single-use code → per-device token + whois); session list with live state (running/waiting/done/exited/external/stopped); start session from phone (cwd allowlist); terminal view (keys, resize, extra-keys bar); chat view from transcript; send input; chat⇄terminal toggle; push on Stop/Notification with deep link; seq-replay reconnect + ConnectionBanner; interrupt/stop; resume after hub restart.

**Differentiators:** read-only watch of external sessions (Even Terminal / plain terminal, labeled by `entrypoint`); take-over via `--resume` with two-writer guard; push body with session name + one-line summary (generic by default for lock screen); no cloud relay.

**Defer (v2+):** permission approve/deny (first v2 add; reuses Notification hook), voice, diff/file browser, multi-user, Android/web, Mac handoff + glasses switcher, ZeeChat compat, Live Activities/widgets, orchestration.

### Architecture Approach

One hub process, 5–7 files (server, sessions, transcript, hooks, apns, store, test). Tailnet-bound listener (whois + bearer) for the app; separate 127.0.0.1 listener for hooks. Per-session EventLog of `{v, seq, kind: term|chat|state}` with epoch/boot id, bounded by bytes, per-socket send limits. TranscriptTailer finds `<uuid>.jsonl` by filename glob (never reverse-encode cwd), whitelists `user`/`assistant`, ignores unknown types, buffers partial lines. Signal-driven state machine with debounce in one tested place. Hooks fire for all PC sessions → unknown `session_id` becomes an `external` record.

Components: Server+Auth (bind Tailscale IP with retry/backoff, never 0.0.0.0; whois + token; pairing; REST + WS) · SessionManager (spawn/kill/resume, input lock, spawn 120x30, only terminal view sends debounced clamped resizes) · EventLog (seq ring, replay, reset) · TranscriptTailer (chat events, titles from `ai-title`/`last-prompt`, external discovery) · HookReceiver + Notifier (state → APNs, collapse-id = session id, 410 deletes token, tokens tagged by env) · iOS Connection / Chat / Terminal layers.

### Critical Pitfalls

1. **Orphaned `claude` trees + two writers** — `taskkill /T /F`, stored PIDs, boot sweep, `--session-id`, single input lock, take-over refuses on recent transcript mtime, externals read-only.
2. **node-pty build/ABI, wrong claude path/env** — pin Node; absolute `node.exe`/`claude.exe` resolved at install; explicit env (`USERPROFILE`, `APPDATA`, `CLAUDE_CODE_GIT_BASH_PATH`, `TERM`); startup self-test spawn.
3. **Hub down after reboot / bind / firewall / whois** — install script: task + firewall rule for `100.64.0.0/10` + port; retry-bind; fail-closed whois (handle tagged nodes, pin login/node id); disable Tailscale key expiry on PC.
4. **Hooks** — Stop fires every turn (debounce); hooks snapshot at session start; merge into `settings.json` with backup + marker; never block Claude.
5. **iOS background + APNs env mismatch** — background = disconnected, push is the channel; ping/pong + NWPathMonitor; store `{token, environment}`, delete only on 410; cache JWT.
6. **Auth is RCE by design** — 8+ char single-use 5-min pairing code from local `hub pair`; header auth; cwd allowlist; never pass `--dangerously-skip-permissions`; never log tokens/transcripts.
7. **Personal-tool rot** — TestFlight 90-day expiry, Tailscale key expiry, deploy drift, Claude format drift → `deploy.ps1`, `/health` with git SHA + protocol version, fixture parser test, `doctor`, "hub started" push.

## Implications for Roadmap

Fix the wire protocol (versioned envelope + REST routes) in Phase 1 so the iOS skeleton can run in parallel against a replay hub.

- **P0 PC spikes** (fold into P1): written findings for the flags below.
- **P1 Hub core** — `claude --session-id` in ConPTY, term events, input, resize clamp, seq replay, versioned envelope, input lock, `taskkill /T`, atomic store, `/health`, replay unit test; CLI/websocat client.
- **P2 Transcript tailer + chat + session list + state** — offset tailer, glob mapping, fixture parser test, external discovery via `entrypoint`, state machine with hysteresis.
- **P3 Hooks** — settings-merge installer/uninstaller, loopback listener, Stop/Notification → state with debounce, external records.
- **P4 Auth, pairing, Tailscale bind, install** — whois + token, `hub pair`, cwd allowlist, retry-bind, `install.ps1` (task, firewall, hooks), rotating logs, RUNBOOK.md.
- **P5 iOS skeleton + connection** (parallel with P1–P4) — XcodeGen, DesignSystem, pairing + Keychain, WS reconnect/seq, ConnectionBanner, session list, decode/seq tests, ws:// ATS spike.
- **P6 Session detail** — Chat, then SwiftTerm (extra-keys bar, per-frame batching, capped scrollback), toggle, new-session UI, replay-corruption check.
- **P7 APNs** — http2 sender, env-tagged registration, deep link, 410 cleanup, collapse-id, `/test-push`, truncation, "hub started" push.
- **P8 Resume, take-over, recovery, ops** — `--resume` with liveness guard, `stopped` state, boot sweep, `deploy.ps1`, `doctor`, health banner, `release.sh`, TestFlight day-60 reminder, Tailscale key expiry off.

v1 done = reconnect + push reliable for 2 weeks of real use.

### Research Flags (on-PC verification)

- **P1:** node-pty prebuild for pinned Node; `claude.exe` resolution under Task Scheduler; Claude TUI under ConPTY (Ctrl-C, arrows, UTF-8, resize, bracketed paste + `\r`); orphan check after tree kill; resize-nudge repaint vs `@xterm/headless`.
- **P2:** Windows project-dir encoding/transcript location; transcript appears only after first prompt; `entrypoint` for CLI vs Even Terminal.
- **P3:** installed `claude --version` honors `type:"http"` hooks + header/secret; command fallback; Stop/Notification/SubagentStop payloads.
- **P4:** `tailscale whois --json` fields (user-owned vs tagged phone); firewall from phone; bind-before-Tailscale timing; hidden-launch behavior.
- **P5/P6:** on-device ws:// ATS; SwiftTerm rendering of Claude TUI (xterm.js fallback); 5 MB burst test.
- **P7:** APNs JWT refresh rule; sandbox vs production on TestFlight.
- **P8:** `--resume` keeps session id?; Even Terminal cwd/id behavior.

Standard patterns (skip research): P5 SwiftUI screens, P7 sender once env/JWT rules applied, P4 token/pairing mechanics.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Versions registry-verified; Windows behavior, http hook, ATS unverified |
| Features | MEDIUM | Competitor data from listings/search; v1 scope from approved spec |
| Architecture | MEDIUM-HIGH | Transcript format + hook docs verified; Windows paths/ConPTY/Even Terminal unverified |
| Pitfalls | MEDIUM | Platform knowledge, items marked [verify] |

**Overall:** MEDIUM

### Gaps
- ZeeChat's actual cause of death unknown (ask Rishi / `legacy-reference/`).
- Auto-logon for unattended reboot is Rishi's decision.
- Even Terminal internals need hands-on PC check.
- Record a transcript fixture on the PC (versions may differ from Mac).
- Pin phone whois login/node id; Tailscale ACL scoping phone → PC:port.
- DesignSystem consumption (local SPM vs `sources:` path) and iOS deployment target — match WorkoutCoach.

## Sources

Primary: npm registry + nodejs.org dist (2026-11-11); node-pty README; https://code.claude.com/docs/en/hooks; local transcripts + `claude --help`; SwiftTerm 1.99.3 + XcodeGen 2.46.0 releases. Secondary: Apple APNs token docs, Tailscale whois/LocalAPI/cert docs, Remote Control bug reports, Happy repo, project spec. Tertiary: Omnara listing, ATS behavior for IP-literal hosts, Task Scheduler details.
