# Feature Landscape

**Domain:** Personal iPhone remote-control app for Claude Code agents (single user, home-PC hub over Tailscale)
**Researched:** 2026-11-11
**Overall confidence:** MEDIUM (competitor features from web search/listings, not hands-on; v1 scope from the approved spec)

Reference products: Claude Code Remote Control (claude.ai / Claude mobile), Happy (slopus/happy), Omnara, Happier, ntfy/hook-based approver scripts, plus terminal clients (Termius, Blink) as the generic fallback.

What the competitors do (sources below):
- **Remote Control (Anthropic):** session must be started on the computer first; one remote connection per instance; terminal must stay open; ~10 min network loss times out; needs claude.ai login. Users report sync bugs (one-way sync, stuck "Disconnected" after restart/compaction). Terminal-only slash commands (`/plugin`, `/resume`) don't work from the app. (MEDIUM)
- **Happy:** open-source mobile/web client; push on permission-needed/error with deep links to the session; E2E encryption (TweetNaCl) via a relay server; voice via LiveKit; device switching phone<->desktop. (MEDIUM)
- **Omnara:** real-time notifications, logs, diffs, one-tap approvals, web+mobile sync via a cloud service. (LOW-MEDIUM)

echo.r2's wedge versus all of them: PC-hosted, phone can START sessions, sessions survive phone/app/terminal closure, no cloud relay (Tailscale only), and a real terminal view alongside chat.

## Table Stakes

Missing = the app is not worth opening instead of SSH + a terminal client.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Pairing + per-device token auth | Every competitor has a pairing step; security baseline | Low-Med | One-time code -> bearer token in Keychain; plus tailnet whois check (spec) |
| Session list with live state | Core "what is every agent doing" value | Low-Med | States: running / waiting for you / done / exited / external / stopped |
| Start new session from phone (dir + optional prompt) | Remote Control lacks this; it is the main reason to build | Med | Needs hub-side project-dir browsing/allowlist |
| Chat view (structured transcript) | All competitors render messages, not raw bytes | Med-High | Parse JSONL: user/assistant/tool-use summary/result; collapse tool noise |
| Send input / steer from chat | "Steer" is the core promise | Low | Writes to the same PTY |
| Terminal view (SwiftTerm) with keystrokes, resize | Needed for TUI prompts, `/` commands, anything chat can't show | High | ConPTY quirks; needs an extra-keys bar (Esc, Tab, Ctrl-C, arrows) on iOS |
| Chat <-> Terminal toggle on one session | Spec's key design bet | Med | Depends on single PTY + transcript tailer |
| Push alerts on done / needs input / exited, tap deep-links to session | The other half of core value; Happy and Omnara both do this | Med | Hooks `Stop`/`Notification` -> hub -> APNs; retry once, drop on 410 |
| Reliable reconnect with no lost output (seq replay) | Remote Control's biggest complaint is flaky sync | Med-High | Bounded ring buffer + `since=<seq>`; ConnectionBanner offline state |
| Sessions persist independent of phone | Basic expectation for remote agents | Low | PTY owned by hub |
| Interrupt/stop a session (Ctrl-C / kill) | Must be able to stop a runaway agent from the phone | Low | Also covered by terminal view keys; add an explicit stop button |
| Resume sessions killed by hub restart | Avoids losing work after PC reboot (a known Remote Control pain) | Low-Med | `claude --resume <id>`; mark `stopped` |
| Offline/connection status indicator | Trust in the displayed state | Low | Reuse DesignSystem ConnectionBanner |

## Differentiators

Not expected, but fit this user's setup.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Watch external sessions (Even Terminal / plain terminal) read-only | See everything on the PC, including glasses-driven sessions | Med | Transcript discovery only; no PTY |
| "Take over" external session into hub | Turn a watched session into a steerable one | Med | `claude --resume`; warn about two writers |
| No cloud relay (Tailscale-only, hub binds tailnet IP) | Privacy; no third-party sees code; discreet | Low (by design) | Strong contrast with Happy/Omnara servers |
| Push contents: session name + one-line summary | Triage without opening the app | Low-Med | Summary from last assistant message in transcript |
| Own palette/logo using shared DesignSystem | Cohesive personal-app feel | Low | Reuse, don't redo |
| Terse, plain output awareness (glasses use) | Matches G2 workflow | Low | Mostly a v2 concern; just avoid emoji-heavy UI strings |

## Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Permission approve/deny buttons (actionable push) | Explicitly v2 (spec "B"); needs `PermissionRequest` hook round-trips and timeouts | v1: Notification push says "needs you"; user answers in terminal/chat view |
| Cloud relay / accounts / E2E crypto layer | Single user on a private tailnet; adds server and key mgmt | Tailscale + token |
| Voice control | Happy's LiveKit voice is heavy and paid; unrequested | Skip; iOS keyboard dictation already works |
| Code diff viewer / file browser / editor | Large scope; terminal and chat already show diffs | Defer; revisit only if missed in use |
| Multi-user, sharing, teams | Personal tool | None |
| Android / web client | iPhone only | None |
| Mac<->PC handoff, glasses switcher | v2 | Keep out of the v1 data model except leaving room for a `host` field |
| ZeeChat / Dispatch `/api/v1/chat` compatibility | Clean break | None |
| Multi-agent orchestration, task queues, scheduling | Scope creep beyond start/watch/steer | None |
| In-app settings for models/MCP/slash-command pickers | Terminal view covers it; Remote Control itself lacks them | Type the command |
| Rich notification actions, widgets, Live Activities, Watch app | Nice but not "reliable alerts" | Possible later if push proves insufficient |
| Session search/history analytics | Not needed for few sessions | Plain list sorted by recent activity |

## Feature Dependencies

```
Hub service + Tailscale bind -> Pairing/token auth -> everything else
PTY session (node-pty) -> Start session -> Terminal view -> Send input
PTY session -> Interrupt/stop
Transcript tailer -> Chat view -> Chat<->Terminal toggle (also needs PTY)
Transcript tailer -> External session discovery -> Watch external -> Take over (needs PTY spawn + --resume)
Session store (JSON/SQLite) -> Session list states -> Resume after hub restart
Seq-numbered event log + ring buffer -> Reconnect/replay (both views)
Hooks installer -> Hook receiver -> APNs sender -> Push deep link (needs Session list/detail routing)
Apple dev cert + .p8 -> APNs + TestFlight build (must exist before push can be tested on device)
```

## MVP Recommendation

Prioritize (in this order, matching dependencies):
1. Hub + auth/pairing + start session + terminal view + input (proves the PTY path on Windows ConPTY, the biggest technical risk)
2. Session list + states + seq-replay reconnect
3. Hooks -> APNs push with deep link (second half of core value; get TestFlight/APNs early since device-only testing)
4. Chat view from transcript + toggle
5. External watch + take over; resume after restart

Defer: everything in Anti-Features; permission approval is the most likely first v2 add since every competitor treats it as the headline feature, and the `Notification` hook plumbing built in step 3 is reusable for it.

## Sources

- Claude Code mobile docs: https://code.claude.com/docs/en/mobile (official, not fully fetched; MEDIUM)
- TechRadar on Remote Control limits: https://www.techradar.com/pro/anthropic-reveals-remote-control-a-mobile-version-of-claude-code-to-keep-you-productive-on-the-move (MEDIUM)
- Remote Control bug reports: https://claudeissues.com/issue/62284-remote-control-can-read-session-from-mobile-but-cannot-send-messages-back , https://claudeissues.com/issue/91592-bug-remote-control-sessions-require-pc-side-input-to-reconnect-after-restart-pho (MEDIUM)
- Happy: https://github.com/slopus/happy , https://apps.apple.com/app/id6748571505 (MEDIUM)
- Omnara: https://www.producthunt.com/products/omnara (LOW)
- Hook-based phone approvers: https://github.com/yuuichieguchi/claude-remote-approver (LOW)
