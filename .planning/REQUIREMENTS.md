# Requirements: echo.r2

**Defined:** 2026-11-11
**Core Value:** From the phone, anywhere, Rishi can see what every Claude session on the home PC is doing and tell it what to do next — and gets pinged the moment one finishes or needs him.

## v1 Requirements

### Hub (PC service)

- [ ] **HUB-01**: Hub starts automatically when Rishi logs into the Windows PC and restarts itself if it crashes
- [ ] **HUB-02**: Hub is reachable only from Rishi's tailnet devices (bound to Tailscale IP; whois check fails closed)
- [ ] **HUB-03**: `/health` reports hub version, git SHA, protocol version, and uptime
- [ ] **HUB-04**: One install script sets up the scheduled task, firewall rule, and Claude hooks on the PC; one deploy script updates the hub from git

### Pairing & Auth

- [ ] **AUTH-01**: Rishi can pair the phone by entering a single-use, 5-minute code printed by a local `hub pair` command
- [ ] **AUTH-02**: Paired phone stays authenticated across app restarts (token in Keychain, sent in header)
- [ ] **AUTH-03**: Rishi can revoke a paired device from the PC; the app returns to pairing on 401

### Sessions

- [ ] **SESS-01**: Rishi can start a new Claude Code session on the PC from the phone, choosing a project directory from an allowlist and an optional first prompt
- [x] **SESS-02**: Rishi can see all sessions with live state: running, waiting for you, done, exited, stopped, external
- [x] **SESS-03**: Sessions keep running when the phone disconnects or the app closes
- [ ] **SESS-04**: Rishi can interrupt (Ctrl-C) or stop a session from the phone; stopping kills the whole process tree
- [ ] **SESS-05**: Only one writer per session — input is serialized and external sessions are read-only
- [ ] **SESS-06**: After a hub restart, previously running sessions show as stopped and Rishi can resume them (`claude --resume`)

### Chat View

- [ ] **CHAT-01**: Rishi can read a session as chat: his messages, Claude's text replies, and one-line tool-use summaries, parsed from the transcript
- [ ] **CHAT-02**: Rishi can send a message to the session from the chat view
- [ ] **CHAT-03**: Chat view updates live as Claude writes

### Terminal View

- [ ] **TERM-01**: Rishi can view the live terminal of a hub-owned session (SwiftTerm), with resize to fit the phone
- [ ] **TERM-02**: Rishi can type into the terminal, with an extra-keys bar (Esc, Tab, Ctrl-C, arrows)
- [ ] **TERM-03**: Rishi can toggle between chat and terminal views of the same session

### External Sessions

- [ ] **EXT-01**: Sessions started outside the hub (Even Terminal, plain terminal `claude`) appear in the list as external, labeled by source, and can be watched read-only in chat view
- [ ] **EXT-02**: Rishi can "Take over" an external session, which resumes it inside the hub after confirming it is no longer active

### Connection

- [ ] **CONN-01**: After a network drop, the app reconnects automatically and shows any output missed (seq replay), with no duplicates
- [ ] **CONN-02**: The app shows a clear banner when the hub is unreachable

### Notifications

- [ ] **NOTF-01**: Rishi gets a push when a session finishes a turn, needs input, or exits — showing the session name and a one-line summary
- [ ] **NOTF-02**: Tapping a push opens that session in the app
- [ ] **NOTF-03**: Pushes work for both debug (sandbox) and TestFlight (production) builds; stale device tokens are cleaned up
- [ ] **NOTF-04**: Rapid repeated hook events for one session collapse into a single push
- [ ] **NOTF-05**: Rishi gets a "hub started" push when the hub comes up, so silent outages are noticed

### App & Distribution

- [ ] **APP-01**: App uses the shared DesignSystem (from WorkoutCoach/ChessCoach) with its own echo.r2 accent and logo
- [ ] **APP-02**: App builds from XcodeGen `project.yml` and ships to Rishi's phone via TestFlight with one release script

## v2 Requirements

### Handoff
- **HAND-01**: PC hub detects whether the Mac agent is online and streams its feed
- **HAND-02**: When the Mac drops, PC resumes the work in the background and Rishi can talk to it
- **HAND-03**: When the Mac returns, it pulls updated code first, then continues locally

### Glasses
- **GLAS-01**: Even Terminal runs on the PC so the G2 glasses can drive PC sessions
- **GLAS-02**: Switcher selects Mac or PC as the glasses' target

### Permissions
- **PERM-01**: Approve or deny Claude permission prompts from a push / the app

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cloud relay / public exposure | Tailscale-only by design; no third party in the path |
| Accounts / multi-user | Personal tool for one user |
| Android / web client | iPhone only |
| ZeeChat / Dispatch chat compatibility | Clean break; Dispatch stays only for Mac↔PC messaging |
| Voice input, diff/file browser | Not requested; Claude TUI covers it in terminal view |
| Live Activities, widgets, Watch app | Not requested for v1 |
| Multi-agent orchestration | Out of v1 scope |
| `--dangerously-skip-permissions` sessions | Phone access is effectively remote code execution; keep Claude's own permission gate |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SESS-02 | Phase 1 | Complete |
| SESS-03 | Phase 1 | Complete |
| SESS-04 | Phase 1 | Pending |
| SESS-05 | Phase 1 | Pending |
| HUB-01 | Phase 2 | Pending |
| HUB-02 | Phase 2 | Pending |
| HUB-03 | Phase 2 | Pending |
| HUB-04 | Phase 2 | Pending |
| AUTH-01 | Phase 2 | Pending |
| AUTH-03 | Phase 2 | Pending |
| APP-01 | Phase 3 | Pending |
| AUTH-02 | Phase 3 | Pending |
| SESS-01 | Phase 3 | Pending |
| CHAT-01 | Phase 3 | Pending |
| CHAT-02 | Phase 3 | Pending |
| CHAT-03 | Phase 3 | Pending |
| TERM-01 | Phase 3 | Pending |
| TERM-02 | Phase 3 | Pending |
| TERM-03 | Phase 3 | Pending |
| EXT-01 | Phase 3 | Pending |
| CONN-01 | Phase 3 | Pending |
| CONN-02 | Phase 3 | Pending |
| NOTF-01 | Phase 4 | Pending |
| NOTF-02 | Phase 4 | Pending |
| NOTF-03 | Phase 4 | Pending |
| NOTF-04 | Phase 4 | Pending |
| NOTF-05 | Phase 4 | Pending |
| SESS-06 | Phase 4 | Pending |
| EXT-02 | Phase 4 | Pending |
| APP-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0 ✓

---
*Requirements defined: 2026-11-11*
*Last updated: 2026-11-11 after roadmap creation*
