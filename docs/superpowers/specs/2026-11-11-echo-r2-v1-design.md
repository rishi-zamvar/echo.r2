# echo.r2 v1 — Design

Date: 2026-11-11. Status: approved (brainstorm). Fresh rebuild of the old ZeeChat app (renamed echo.r2); old app archived in `legacy-reference/` (gitignored, reference only).

## Goal
iPhone app to start, watch, and steer Claude Code sessions running on the always-on home PC, and get reliable alerts from them. The PC is the hub because the Mac travels and goes offline.

## Scope
**v1 (this spec)**
- A. Start, watch, steer Claude Code sessions on the PC from the phone.
- C. Reliable alerts + chat with agents (APNs push).

**v2 (out of scope, recorded for roadmap)**
- Mac↔PC handoff: PC hub watches whether the Mac agent is online, streams its feed; when the Mac drops, PC resumes the work in the background and the user talks to it; when the Mac returns it first pulls updated code, then continues locally.
- Even Realities G2 glasses linked to the PC: run Even Terminal on the PC; a switcher picks Mac or PC as the target.
- Permission-prompt approval from the phone (B) — not requested for v1.

## Environment facts
- PC: Windows, Claude Code installed natively (no WSL, no tmux). Tailscale node `zee-cloud` (100.91.236.115), Tailscale exit node.
- Mac: `rishis-macbook-pro`, intermittent. Dispatch daemon remains for Mac↔PC messaging; not used by echo.r2 v1.
- Paid Apple Developer account → TestFlight distribution, real APNs.
- Even Terminal (`@evenrealities/even-terminal`, Node, supports Windows) drives Claude via the Agent SDK with `--resume <session-id>`, writing standard transcripts.

## Architecture
```
iPhone app ──(Tailscale, WSS + token)──► PC hub (Node, Windows)
                                          ├─ node-pty (ConPTY) per hub-owned session: `claude` CLI
                                          ├─ transcript tailer: ~/.claude/projects/**/*.jsonl
                                          ├─ hook receiver: Claude Code Stop / Notification hooks → POST
                                          └─ APNs sender (.p8 token auth)
```

### PC hub (Node service)
- Starts at Windows login (Task Scheduler). Binds to the Tailscale IP only.
- Auth: request must come from a tailnet peer owned by the user (Tailscale whois) AND carry a per-device bearer token (stored in iOS Keychain). Pairing: hub prints a one-time code; app exchanges it for the token.
- Session model: one `claude` process per hub-owned session in a ConPTY via `node-pty`. Process lives independently of phone connections. Hub keeps a bounded raw-output scrollback ring buffer per session for terminal-view replay.
- Two views of the same session:
  - **Chat view:** tail the session's transcript JSONL, emit structured messages (user / assistant text / tool use summary / result).
  - **Terminal view:** raw PTY byte stream + resize; keystrokes written to the PTY.
  - Input from either view goes into the same PTY.
- External sessions (Even Terminal, plain terminal claude) discovered from transcripts: **watch-only**. "Take over" = spawn `claude --resume <id>` inside the hub; the external process should be stopped first (user's responsibility in v1; app warns).
- Alerts: hub installs Claude Code hooks (`Stop`, `Notification`) in PC user settings that POST to the hub on loopback; hub turns them into APNs pushes (session name + one-line summary). Deep link opens that session.
- Persistence: small JSON/SQLite store for sessions (id, cwd, title, state), device tokens, APNs tokens.

### iOS app (SwiftUI)
- Design language: reuse the shared `DesignSystem/` from WorkoutCoach-iOS / ChessCoach-iOS (Palette, Typography, Spacing, Components, Atmosphere, ConnectionBanner, Toast, Haptics, Animations); echo.r2 gets its own palette accent + logo.
- Screens: Sessions list (live state: running / waiting for you / done / external) → Session detail with Chat ⇄ Terminal toggle → New session (pick project dir on PC, optional first prompt) → Settings (pairing, notifications).
- Terminal view: SwiftTerm.
- Connection: WebSocket with auto-reconnect + resume from last event seq; ConnectionBanner shows offline state. Push notifications cover the app-backgrounded case.
- Project: XcodeGen `project.yml` (pbxproj gitignored), TestFlight via paid account.

## Data flow
1. App → hub `POST /sessions {cwd, prompt?}` → hub spawns PTY, returns id.
2. App opens `WSS /sessions/:id/stream?view=chat|term&since=<seq>` → hub replays from seq then streams live.
3. App sends `{type:"input", text}` or raw keys → hub writes to PTY.
4. Claude hook fires → hub → APNs → phone notification → tap opens session.

## Error handling
- Hub restart: hub-owned sessions die with it; on restart they are marked `stopped` and offered as "resume" (`claude --resume <id>`) since transcripts persist.
- Phone disconnect: no effect on sessions; reconnect resumes by seq.
- PTY exit: session marked `exited` with exit code; push sent.
- APNs failure: log + retry once; stale device token removed on 410.
- Auth failure: 401, app returns to pairing.

## Testing
- Hub: one runnable test file covering transcript-to-chat parsing, seq replay, and auth rejection; manual smoke on the PC (spawn, stream, input, hook → push).
- iOS: unit test for stream decoding + reconnect/seq logic; simulator build via XcodeGen + xcodebuild; TestFlight build on device.
