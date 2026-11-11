# echo.r2

## What This Is

echo.r2 ("Echo", a second Rishi, in the spirit of R2-D2) is a personal, discreet iPhone app for Rishi Zamvar to start, watch, and steer Claude Code agents running on his always-on home PC, and to get reliable alerts from them. The home PC (Windows, California, Tailscale exit node) is the hub; the Mac travels and drops offline, so it cannot be the source of truth. It is a fresh rebuild of the defunct ZeeChat app.

## Core Value

From the phone, anywhere, Rishi can see what every Claude session on the home PC is doing and tell it what to do next — and gets pinged the moment one finishes or needs him.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] PC hub service (Node, Windows) runs at login, reachable only over Tailscale, paired to the phone with a per-device token
- [ ] Start a new Claude Code session on the PC from the phone (choose project dir, optional first prompt)
- [ ] List all sessions with live state (running / waiting for you / done / exited / external)
- [ ] Chat view of a session (structured messages parsed from the transcript JSONL)
- [ ] Terminal view of the same session (live PTY stream, keystrokes, resize), toggle between views
- [ ] Send input to a session from either view
- [ ] Watch external sessions (Even Terminal, plain terminal `claude`) read-only; "Take over" resumes them inside the hub
- [ ] Push notification (APNs) when a session finishes, needs input, or exits; tapping opens that session
- [ ] Reconnect seamlessly after network drops without losing output (seq-based replay)
- [ ] Sessions killed by a hub restart are offered for resume
- [ ] App uses the shared design language (DesignSystem from WorkoutCoach/ChessCoach) with its own accent + logo
- [ ] Distributed via TestFlight

### Out of Scope

- Mac↔PC handoff (PC watches Mac agent, takes over when Mac drops, Mac pulls code and resumes when back) — v2, next milestone
- Even Realities G2 glasses linked to the PC + Mac/PC switcher (Even Terminal on the PC) — v2, next milestone
- Approving/denying permission prompts from the phone — not requested for v1
- Old ZeeChat / Dispatch `/api/v1/chat` compatibility — clean break; Dispatch stays only for Mac↔PC messaging
- Multi-user / accounts — single user, personal tool
- Android / web client — iPhone only

## Context

- PC: Windows, Claude Code installed natively (no WSL, no tmux → ConPTY via `node-pty`). Tailscale node `zee-cloud` (100.91.236.115).
- Mac: `rishis-macbook-pro`, intermittent connectivity. Development happens on the Mac; hub code is deployed to the PC (via git; PC-side Claude "swe" reachable through Dispatch).
- Even Terminal (`@evenrealities/even-terminal` 0.10.x, Node, Windows-capable) drives Claude via the Agent SDK with `--resume <id>`; its sessions write standard transcripts under `~/.claude/projects/`.
- Claude Code hooks (`Stop`, `Notification`) are the signal source for alerts.
- Design system to reuse: `~/Documents/Projects/WorkoutCoach-iOS/WorkoutCoach/DesignSystem/` (Palette, Typography, Spacing, Components, Atmosphere, ConnectionBanner, Toast, Haptics, Animations, Logo).
- Old ZeeChat artifacts (skill, commands, memory notes) archived in `legacy-reference/` (gitignored) for reference only.
- User often drives Claude from Even Realities G2 glasses — output on the glasses must be terse and plain.
- Approved design spec: `docs/superpowers/specs/2026-11-11-echo-r2-v1-design.md`.

## Constraints

- **Tech stack (hub)**: Node + `node-pty` on native Windows — Even Terminal is Node and ConPTY support is best there.
- **Tech stack (app)**: SwiftUI, XcodeGen `project.yml` (pbxproj gitignored), SwiftTerm for terminal view.
- **Network/Security**: Hub binds to Tailscale IP only; requests need tailnet whois match AND bearer token. No public exposure.
- **Distribution**: Paid Apple Developer account → TestFlight + APNs (.p8 token auth).
- **Simplicity**: Ponytail rules — stdlib/native first, minimal deps, fewest files.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| PC is the hub; phone talks only to PC | Mac travels and goes offline; PC is always on | — Pending |
| New Node hub, not extending Dispatch daemon | Best Windows PTY support, matches Even Terminal, avoids legacy code | — Pending |
| One PTY session, two views (chat from transcript, terminal from PTY) | Flexibility without running two processes | — Pending |
| External sessions watch-only; take over via `claude --resume` | Avoid two writers on one session | — Pending |
| APNs via TestFlight build | Paid account available; reliable push | — Pending |
| Fresh rebuild, name echo.r2 | Old ZeeChat defunct; personal + discreet name | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-11 after initialization*
