# Roadmap: echo.r2

## Overview

High-risk Windows/ConPTY work goes first and is proven from a CLI client (no iOS UI needed). Next the hub is locked down (Tailscale bind, pairing, install) so it runs unattended on the PC. Then the iOS app is built against a real hub. Last: push, resume/take-over, and TestFlight release. Research suggested 8 phases; consolidated to 4 for coarse granularity.

## Phases

- [ ] **Phase 1: Hub Session Engine** - Node hub on the PC runs Claude sessions in ConPTY, tracks live state, replays output; driven by a CLI client
- [ ] **Phase 2: Secure Hub & PC Install** - Hub is tailnet-only, token-paired, auto-starts at login, one-command install/deploy
- [ ] **Phase 3: iOS App** - Paired app lists sessions, starts them, shows chat and terminal, watches external sessions, reconnects cleanly
- [ ] **Phase 4: Push, Recovery & Release** - APNs alerts with deep links, resume/take-over, TestFlight release

## Phase Details

### Phase 1: Hub Session Engine
**Goal**: A hub on the Windows PC runs and supervises Claude Code sessions that outlive any client, and a CLI client can see state, send input, interrupt, and stop them.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: SESS-02, SESS-03, SESS-04, SESS-05
**Success Criteria** (what must be TRUE):
  1. From a CLI client, a session started in the hub keeps running after the client disconnects, and a reconnect with `since=<seq>` returns missed output with no duplicates.
  2. The session list shows each session as running / waiting for you / done / exited / stopped / external, driven by hooks and PTY exit rather than screen scraping.
  3. Interrupt (Ctrl-C) reaches Claude, and Stop kills the whole process tree (no orphaned `claude` processes on the PC afterwards).
  4. Input from two clients to one session is serialized; input to an external session is refused.
**Plans**: 6 plans
Plans:
- [ ] 01-01-PLAN.md — Walking skeleton: CLI starts real Claude in hub, attach/detach, since/epoch replay (SESS-03)
- [ ] 01-02-PLAN.md — Live state via http hooks (--settings) + transition() + cli list (SESS-02)
- [ ] 01-03-PLAN.md — Send/interrupt/stop, serialized writers, tree kill, boot sweep (SESS-04, SESS-05)
- [ ] 01-04-PLAN.md — Transcript chat events + external session discovery, read-only (SESS-02, SESS-05)
- [ ] 01-05-PLAN.md — Push to private GitHub, PC spikes S1-S7 via Dispatch, 01-SPIKES.md (parallel with 01-02)
- [ ] 01-06-PLAN.md — PC acceptance of success criteria 1-4 via Dispatch
**On-PC spikes** (written findings before building on them):
  - node-pty prebuild for the pinned Node; `claude.exe` resolution under Task Scheduler
  - Claude TUI under ConPTY: Ctrl-C, arrows, UTF-8, resize, bracketed paste + `\r`; orphan check after tree kill; resize-nudge repaint vs `@xterm/headless`
  - Transcript location/encoding on Windows; transcript appears only after first prompt; `entrypoint` for CLI vs Even Terminal
  - Installed `claude --version` honors `type:"http"` hooks and a secret (fallback: command hook `node hook.js`); Stop/Notification/SubagentStop payloads
  - Record a transcript fixture on the PC for the parser test

### Phase 2: Secure Hub & PC Install
**Goal**: The hub is reachable only by Rishi's paired phone over Tailscale and keeps itself running on the PC with one install and one deploy command.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: HUB-01, HUB-02, HUB-03, HUB-04, AUTH-01, AUTH-03
**Success Criteria** (what must be TRUE):
  1. After a PC reboot and login, the hub is running with no manual step, and it restarts itself if killed.
  2. A request from outside the tailnet, or from a tailnet device without a valid token, is rejected (fail closed); the hub is not bound to 0.0.0.0.
  3. `hub pair` prints a single-use code that expires in 5 minutes and exchanges for a per-device token; `hub revoke` makes that device get 401.
  4. `/health` reports hub version, git SHA, protocol version, and uptime.
  5. One install script sets up the scheduled task, firewall rule, and Claude hooks; one deploy script updates the hub from git.
**Plans**: TBD
**On-PC spikes**:
  - `tailscale whois --json` fields for the phone (user-owned vs tagged); firewall reachability from the phone
  - Bind-before-Tailscale timing (retry-bind); hidden-launch behavior under Task Scheduler

### Phase 3: iOS App
**Goal**: Rishi can pair the phone and, from anywhere, see every session, start new ones, read and steer them in chat or terminal, and trust the connection to recover.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: APP-01, AUTH-02, SESS-01, CHAT-01, CHAT-02, CHAT-03, TERM-01, TERM-02, TERM-03, EXT-01, CONN-01, CONN-02
**Success Criteria** (what must be TRUE):
  1. User can pair with a code once, then relaunch the app and still be connected (token in Keychain); the app uses the shared DesignSystem with the echo.r2 accent and logo.
  2. User can start a new session by choosing an allowlisted project directory and an optional first prompt, and see it in the session list with live state.
  3. User can read a session as chat (his messages, Claude replies, one-line tool summaries), see it update live, and send a message.
  4. User can open the live terminal (resize to fit, extra-keys bar with Esc/Tab/Ctrl-C/arrows), type into it, and toggle to chat and back.
  5. External sessions (Even Terminal, plain `claude`) appear labeled by source and open read-only in chat.
  6. After a network drop the app reconnects by itself, shows missed output without duplicates, and shows a banner while the hub is unreachable.
**Plans**: TBD
**UI hint**: yes
**On-device spikes**:
  - Plain `ws://` over Tailscale vs ATS exception on a real iPhone
  - SwiftTerm rendering of the Claude TUI (xterm.js-in-WKWebView fallback); 5 MB burst test; replay-corruption check
  - DesignSystem consumption (local SPM vs `sources:` path) and deployment target matched to WorkoutCoach

### Phase 4: Push, Recovery & Release
**Goal**: Rishi is pinged the moment a session finishes or needs him, can recover sessions after hub restarts or take over external ones, and the app ships via TestFlight.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: NOTF-01, NOTF-02, NOTF-03, NOTF-04, NOTF-05, SESS-06, EXT-02, APP-02
**Success Criteria** (what must be TRUE):
  1. When a session finishes a turn, needs input, or exits, the phone gets a push with session name and one-line summary; tapping it opens that session.
  2. Pushes work in both debug (sandbox) and TestFlight (production) builds; stale tokens are removed on 410; rapid repeated hook events collapse into one push.
  3. When the hub starts, the phone gets a "hub started" push.
  4. After a hub restart, previously running sessions show as stopped and can be resumed with `claude --resume`.
  5. User can "Take over" an external session; the hub refuses while its transcript shows recent activity, otherwise resumes it inside the hub.
  6. One release script builds from XcodeGen `project.yml` and uploads to TestFlight.
**Plans**: TBD
**UI hint**: yes
**On-PC / on-device spikes**:
  - APNs JWT refresh rule; sandbox vs production token on a TestFlight build
  - `--resume` keeps the session id?; Even Terminal cwd/id behavior

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Hub Session Engine | 0/6 | Not started | - |
| 2. Secure Hub & PC Install | 0/TBD | Not started | - |
| 3. iOS App | 0/TBD | Not started | - |
| 4. Push, Recovery & Release | 0/TBD | Not started | - |
