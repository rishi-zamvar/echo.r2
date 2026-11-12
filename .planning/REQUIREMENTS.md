# Requirements: echo.r2

**Defined:** 2026-11-11
**Core Value:** From the phone, anywhere, Rishi can see what every Claude session on the home PC is doing and tell it what to do next — and gets pinged the moment one finishes or needs him.

## v1 Requirements

### Hub (PC service)

- [x] **HUB-01**: Hub starts automatically when Rishi logs into the Windows PC and restarts itself if it crashes
- [x] **HUB-02**: Hub is reachable only from Rishi's tailnet devices (bound to Tailscale IP; whois check fails closed)
- [x] **HUB-03**: `/health` reports hub version, git SHA, protocol version, and uptime
- [x] **HUB-04**: One install script sets up the scheduled task, firewall rule, and Claude hooks on the PC; one deploy script updates the hub from git

### Pairing & Auth

- [x] **AUTH-01**: Rishi can pair the phone by entering a single-use, 5-minute code printed by a local `hub pair` command
- [x] **AUTH-02**: Paired phone stays authenticated across app restarts (token in Keychain, sent in header)
- [x] **AUTH-03**: Rishi can revoke a paired device from the PC; the app returns to pairing on 401

### Sessions

- [x] **SESS-01**: Rishi can start a new Claude Code session on the PC from the phone, choosing a project directory from an allowlist and an optional first prompt
- [x] **SESS-02**: Rishi can see all sessions with live state: running, waiting for you, done, exited, stopped, external
- [x] **SESS-03**: Sessions keep running when the phone disconnects or the app closes
- [x] **SESS-04**: Rishi can interrupt (Ctrl-C) or stop a session from the phone; stopping kills the whole process tree
- [x] **SESS-05**: Only one writer per session — input is serialized and external sessions are read-only
- [ ] **SESS-06**: After a hub restart, previously running sessions show as stopped and Rishi can resume them (`claude --resume`)

### Chat View

- [x] **CHAT-01**: Rishi can read a session as chat: his messages, Claude's text replies, and one-line tool-use summaries, parsed from the transcript
- [x] **CHAT-02**: Rishi can send a message to the session from the chat view
- [x] **CHAT-03**: Chat view updates live as Claude writes

### Terminal View

- [x] **TERM-01**: Rishi can view the live terminal of a hub-owned session (SwiftTerm), with resize to fit the phone
- [x] **TERM-02**: Rishi can type into the terminal, with an extra-keys bar (Esc, Tab, Ctrl-C, arrows)
- [x] **TERM-03**: Rishi can toggle between chat and terminal views of the same session

### External Sessions

- [x] **EXT-01**: Sessions started outside the hub (Even Terminal, plain terminal `claude`) appear in the list as external, labeled by source, and can be watched read-only in chat view
- [ ] **EXT-02**: Rishi can "Take over" an external session, which resumes it inside the hub after confirming it is no longer active

### Connection

- [x] **CONN-01**: After a network drop, the app reconnects automatically and shows any output missed (seq replay), with no duplicates
- [x] **CONN-02**: The app shows a clear banner when the hub is unreachable

### Notifications

- [ ] **NOTF-01**: Rishi gets a push when a session finishes a turn, needs input, or exits — showing the session name and a one-line summary
- [ ] **NOTF-02**: Tapping a push opens that session in the app
- [x] **NOTF-03**: Pushes work for both debug (sandbox) and TestFlight (production) builds; stale device tokens are cleaned up
- [ ] **NOTF-04**: Rapid repeated hook events for one session collapse into a single push
- [x] **NOTF-05**: Rishi gets a "hub started" push when the hub comes up, so silent outages are noticed

### App & Distribution

- [x] **APP-01**: App uses the shared DesignSystem (from WorkoutCoach/ChessCoach) with its own echo.r2 accent and logo
- [ ] **APP-02**: App builds from XcodeGen `project.yml` and ships to Rishi's phone via TestFlight with one release script

## v1.1 Requirements (Phase 5: Safety, Chat and UI Rebuild)

Source: `docs/v1.1-UPDATE.md`, `.planning/phases/05-v1-1-safety-chat-and-ui-rebuild/05-CONTEXT.md`.

### Safety
- [ ] **V11-01**: The hub never kills a process it did not spawn (boot sweep needs the exact session id on the command line and a non-Even-Terminal parent; stop only kills PIDs spawned this boot); a harness proves 0 external kills over 50 restarts
- [ ] **V11-02**: echo touches nothing in Even Terminal's Claude config: global hooks are opt-in (`--global-hooks`), external state/alerts come from the transcript
- [ ] **V11-03**: Take over / Resume is refused, with a clear message, for Even Terminal (`sdk-ts`) sessions and for any session a live process still references

### Push
- [ ] **V11-04**: Push failures are explained in plain language in the app (test push result + hub `pushLastError`)

### Chat & sessions
- [ ] **V11-05**: Every session (hub-owned, stopped, exited, external, dormant) opens with its full chat history from the transcript, also after hub restarts, merged with the live stream without duplicates
- [ ] **V11-06**: External sessions show "Watching — started in <source>" with a Continue here action; hub-owned sessions always accept input and send works end to end
- [ ] **V11-07**: The session list shows a one-line summary per session, hides noise in a collapsed "Other" section, sorts active first then by last activity, and colours active vs inactive distinctly
- [ ] **V11-08**: The phone pairs itself with no code when the request comes from the owner's untagged tailnet device; code pairing remains as fallback and strips non-alphanumerics

### UI
- [ ] **V11-09**: The UI is rebuilt to one written design direction (apothecary language, no black surfaces, light terminal by default, designed empty/loading/error states, chat bubbles with markdown and collapsed tool rows)
- [ ] **V11-10**: Navigation, list and state changes use spring motion without layout jumps (Reduce Motion respected) and meaningful interactions fire haptics
- [ ] **V11-11**: VoiceOver labels on every control, Dynamic Type up to XXL without truncating key info, WCAG AA contrast

### Testing & release
- [ ] **V11-12**: Rigorous frontend test suite: simulator snapshot tests for every screen at default and XXL, XCUITest flows against a deterministic mock hub, accessibility audits, plus hub node:test coverage for every new endpoint and guard
- [ ] **V11-13**: The app tolerates Tailscale relay latency (request timeouts >= 10 s, quiet reconnects under 3 s)
- [ ] **V11-14**: echo 0.2.0 ships to TestFlight via release.sh (export compliance skipped) and passes the on-device checklist, including push after the APNs key fix

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
| SESS-04 | Phase 1 | Complete |
| SESS-05 | Phase 1 | Complete |
| HUB-01 | Phase 2 | Complete |
| HUB-02 | Phase 2 | Complete |
| HUB-03 | Phase 2 | Complete |
| HUB-04 | Phase 2 | Complete |
| AUTH-01 | Phase 2 | Complete |
| AUTH-03 | Phase 2 | Complete |
| APP-01 | Phase 3 | Complete |
| AUTH-02 | Phase 3 | Complete |
| SESS-01 | Phase 3 | Complete |
| CHAT-01 | Phase 3 | Complete |
| CHAT-02 | Phase 3 | Complete |
| CHAT-03 | Phase 3 | Complete |
| TERM-01 | Phase 3 | Complete |
| TERM-02 | Phase 3 | Complete |
| TERM-03 | Phase 3 | Complete |
| EXT-01 | Phase 3 | Complete |
| CONN-01 | Phase 3 | Complete |
| CONN-02 | Phase 3 | Complete |
| NOTF-01 | Phase 4 | Pending |
| NOTF-02 | Phase 4 | Pending |
| NOTF-03 | Phase 4 | Complete |
| NOTF-04 | Phase 4 | Pending |
| NOTF-05 | Phase 4 | Complete |
| SESS-06 | Phase 4 | Pending |
| EXT-02 | Phase 4 | Pending |
| APP-02 | Phase 4 | Pending |
| V11-01 | Phase 5 | Pending |
| V11-02 | Phase 5 | Pending |
| V11-03 | Phase 5 | Pending |
| V11-04 | Phase 5 | Pending |
| V11-05 | Phase 5 | Pending |
| V11-06 | Phase 5 | Pending |
| V11-07 | Phase 5 | Pending |
| V11-08 | Phase 5 | Pending |
| V11-09 | Phase 5 | Pending |
| V11-10 | Phase 5 | Pending |
| V11-11 | Phase 5 | Pending |
| V11-12 | Phase 5 | Pending |
| V11-13 | Phase 5 | Pending |
| V11-14 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0 ✓
- v1.1 requirements: 14 total (V11-01..V11-14), all mapped to Phase 5

---
*Requirements defined: 2026-11-11*
*Last updated: 2026-11-12 after Phase 5 planning (v1.1 requirements added)*
