# Roadmap: echo.r2

## Overview

High-risk Windows/ConPTY work goes first and is proven from a CLI client (no iOS UI needed). Next the hub is locked down (Tailscale bind, pairing, install) so it runs unattended on the PC. Then the iOS app is built against a real hub. Last: push, resume/take-over, and TestFlight release. Research suggested 8 phases; consolidated to 4 for coarse granularity.

## Phases

- [ ] **Phase 1: Hub Session Engine** - Node hub on the PC runs Claude sessions in ConPTY, tracks live state, replays output; driven by a CLI client
- [ ] **Phase 2: Secure Hub & Install (Mac stand-in + PC)** - Hub is tailnet-only, token-paired, auto-starts at login on the Mac (launchd, live now) and the PC (Task Scheduler, verified when PC returns)
- [x] **Phase 3: iOS App** - Paired app lists sessions, starts them, shows chat and terminal, watches external sessions, reconnects cleanly (completed 2026-11-12)
- [ ] **Phase 4: Push, Recovery & Release** - APNs alerts with deep links, resume/take-over, TestFlight release
- [ ] **Phase 5: v1.1 Safety, Chat and UI Rebuild** - Even Terminal safety, history + Continue here, clean list, auto-pair, UI rebuild with snapshot/XCUITest suite, 0.2.0

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
- [x] 01-01-PLAN.md — Walking skeleton: CLI starts real Claude in hub, attach/detach, since/epoch replay (SESS-03)
- [x] 01-02-PLAN.md — Live state via http hooks (--settings) + transition() + cli list (SESS-02)
- [x] 01-03-PLAN.md — Send/interrupt/stop, serialized writers, tree kill, boot sweep (SESS-04, SESS-05)
- [x] 01-04-PLAN.md — Transcript chat events + external session discovery, read-only (SESS-02, SESS-05)
- [ ] 01-05-PLAN.md — Push to private GitHub, PC spikes S1-S7 via Dispatch, 01-SPIKES.md (parallel with 01-02)
- [ ] 01-06-PLAN.md — PC acceptance of success criteria 1-4 via Dispatch
**On-PC spikes** (written findings before building on them):
  - node-pty prebuild for the pinned Node; `claude.exe` resolution under Task Scheduler
  - Claude TUI under ConPTY: Ctrl-C, arrows, UTF-8, resize, bracketed paste + `\r`; orphan check after tree kill; resize-nudge repaint vs `@xterm/headless`
  - Transcript location/encoding on Windows; transcript appears only after first prompt; `entrypoint` for CLI vs Even Terminal
  - Installed `claude --version` honors `type:"http"` hooks and a secret (fallback: command hook `node hook.js`); Stop/Notification/SubagentStop payloads
  - Record a transcript fixture on the PC for the parser test

### Phase 2: Secure Hub & Install (Mac stand-in + PC)
**Goal**: The hub is reachable only by Rishi's paired phone over Tailscale and keeps itself running with one install and one deploy command. **PC is down ~1 month (from 2026-11-11): the Mac (`rishis-macbook-pro`, 100.125.215.102) is the real stand-in hub now (launchd); Windows install (Task Scheduler/firewall) is written now and verified when the PC returns.**
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: HUB-01, HUB-02, HUB-03, HUB-04, AUTH-01, AUTH-03
**Success Criteria** (what must be TRUE):
  1. After a Mac login (launchd LaunchAgent) — and later a PC reboot+login (Task Scheduler) — the hub is running with no manual step, and it restarts itself if killed.
  2. A request from outside the tailnet, or from a tailnet device without a valid token, is rejected (fail closed); the hub is not bound to 0.0.0.0.
  3. `hub pair` prints a single-use code that expires in 5 minutes and exchanges for a per-device token; `hub revoke` makes that device get 401.
  4. `/health` reports hub version, git SHA, protocol version, and uptime.
  5. One install script per OS (`install.sh` launchd on Mac; `install.ps1` scheduled task + firewall on PC) sets up autostart and Claude hooks; one deploy script updates the hub from git.
**Plans**: 7 plans
Plans:
- [x] 02-01-PLAN.md — Tailnet listener (retry-bind) + whois fail-closed + /health gitSha (HUB-02, HUB-03)
- [x] 02-02-PLAN.md — Pair code → bearer token, devices/revoke, cli pair/devices/revoke (AUTH-01, AUTH-03, HUB-02)
- [x] 02-03-PLAN.md — cwd allowlist + /sessions/roots, /hook/ext global-hook receiver, rotating hub.log (HUB-02, HUB-04)
- [x] 02-04-PLAN.md — Mac install.sh/uninstall.sh/deploy.sh (launchd), hooks-merge.js, RUNBOOK (HUB-01, HUB-04)
- [x] 02-05-PLAN.md — Windows install.ps1/uninstall.ps1/deploy.ps1, written UNVERIFIED (HUB-01, HUB-04)
- [x] 02-06-PLAN.md — Mac live install + checks L1-L8, key-expiry checkpoint (all reqs; human-verify)
- [ ] 02-07-PLAN.md — PARKED: PC verification via swe when zee-cloud returns
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
**Plans**: 5 plans
Plans:
- [x] 03-01-PLAN.md — XcodeGen + SwiftTerm probe, Core (Models/Keychain/HubClient) + macOS tests, DesignSystem + echo wordmark + AppModel, Pairing + Settings (APP-01, AUTH-02)
- [x] 03-02-PLAN.md — Sessions list (3 s poll, chips, externals labeled), New Session sheet, ConnectionBanner + 401 to Pairing (SESS-01, EXT-01, CONN-02, AUTH-02)
- [x] 03-03-PLAN.md — Frame/Replay reducer (TDD, seeded-cursor reconnect test), SessionStream actor (initialState, ping timeout, backoff, NWPath, 4404/4401) (CONN-01, CHAT-03)
- [x] 03-04-PLAN.md — Navigation + SessionDetailModel (retained cursor), Chat view, send/interrupt/stop, external read-only (CHAT-01..03, CONN-01, EXT-01)
- [x] 03-05-PLAN.md — SwiftTerm terminal, extra-keys bar, Chat/Terminal toggle, trust-dialog detector + banner (TERM-01..03)
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
**Plans**: 7 plans
Plans:
- [x] 04-01-PLAN.md — hub/apns.js (JWT, env routing, 410 cleanup, retry), device push tokens, /devices/push(+test), hub-started push, cli test-push (NOTF-03, NOTF-05)
- [x] 04-02-PLAN.md — Finish / needs-input / exit alerts for hub + external sessions, 10 s per-session collapse (NOTF-01, NOTF-04)
- [x] 04-03-PLAN.md — Resume (stopped/exited) + Take over with busy guard, cli resume/takeover, deploy to live Mac hub (SESS-06, EXT-02)
- [x] 04-04-PLAN.md — App: aps-environment, AppDelegate token registration (env-tagged), foreground banner, tap deep link (NOTF-02, NOTF-03)
- [x] 04-05-PLAN.md — App: Resume / Take over in session detail, Settings Notifications card + Send test push (SESS-06, EXT-02, NOTF-03)
- [x] 04-06-PLAN.md — release.sh + ExportOptions.plist, build number from CURRENT_PROJECT_VERSION, AppIcon (APP-02)
- [ ] 04-07-PLAN.md — CHECKPOINT: Rishi's Apple/disk/Tailscale prerequisites, APNs key on live hub, TestFlight upload, on-device checklist incl. Phase 3 items (all reqs)
**UI hint**: yes
**On-PC / on-device spikes**:
  - APNs JWT refresh rule; sandbox vs production token on a TestFlight build
  - `--resume` keeps the session id?; Even Terminal cwd/id behavior

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Hub Session Engine | 4/6 | In Progress|  |
| 2. Secure Hub & PC Install | 6/7 | In Progress|  |
| 3. iOS App | 5/5 | Complete   | 2026-11-12 |
| 4. Push, Recovery & Release | 6/7 | In Progress|  |
| 5. v1.1 Safety, Chat and UI Rebuild | 0/12 | Planned |  |

### Phase 5: v1.1 Safety, Chat and UI Rebuild

**Goal:** echo never disturbs Even Terminal, chat works for every session (history, Continue here, send), the list is clean and summarized, pairing is zero-tap, and the UI is rebuilt to a polished, haptic, accessible, test-locked standard — shipped as TestFlight 0.2.0.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements**: V11-01, V11-02, V11-03, V11-04, V11-05, V11-06, V11-07, V11-08, V11-09, V11-10, V11-11, V11-12, V11-13, V11-14
**Success Criteria** (what must be TRUE):
  1. 50 hub restarts plus every app action while an Even Terminal session is mid-turn never kill it; installs never touch ~/.claude/settings.json by default; Even Terminal sessions cannot be taken over.
  2. Any session (stopped, exited, external, after hub restart) opens with its full chat history; externals offer Continue here; a message sent to a hub-owned session gets a reply in chat.
  3. The list shows one-line summaries, hides noise under "Other", sorts active first, and colours active vs idle distinctly.
  4. A fresh install pairs itself with no code on the owner's phone; code pairing still works as fallback.
  5. Test push failures read in plain language; after the APNs key is set to Sandbox & Production, push arrives on the TestFlight build.
  6. The UI follows one design direction with no black surfaces, spring motion, haptics and VoiceOver/Dynamic Type/AA contrast, enforced by snapshot tests (default + XXL), XCUITest flows on a mock hub and accessibility audits.
  7. echo 0.2.0 is on TestFlight and Rishi approves the on-device checklist.
**Plans:** 12 plans

Plans:
- [ ] 05-01-PLAN.md — P0-1 kill guards (spawned-PID set, Even Terminal parent check, kill log) + 50-restart safety harness (V11-01)
- [ ] 05-02-PLAN.md — Simulator test harness: SnapshotTesting + XCUITest targets, mock hub, test.sh, DEBUG launch hooks (V11-12) [parallel with 05-01]
- [ ] 05-03-PLAN.md — Global hooks opt-in, transcript-derived external alerts, D-03 take-over/resume guards, deploy (V11-02, V11-03)
- [ ] 05-04-PLAN.md — History endpoint + indexed chat events, summary/noise/lastActivity, 7-day dormant externals, deploy (V11-05, V11-07)
- [ ] 05-05-PLAN.md — POST /pair/auto (owner, tagged, revoke deny-list, rate limit) + plain APNs errors/pushLastError, deploy (V11-04, V11-08)
- [ ] 05-06-PLAN.md — App: history for every session, Continue here + refusals, always-on composer, relay tolerance, live-hub send proof (V11-03, V11-05, V11-06, V11-13) [parallel with 05-05]
- [ ] 05-07-PLAN.md — App: auto-pair + code fix, list summary/Other/sort/tones, Settings push messages (V11-04, V11-07, V11-08)
- [ ] 05-08-PLAN.md — UI rebuild 1: impeccable critique → DESIGN.md + tokens; List, Pairing, Settings, New Session with motion/haptics/a11y (V11-09..11)
- [ ] 05-09-PLAN.md — UI rebuild 2: chat bubbles/markdown/tool groups/working/jump pill, header, Chat↔Terminal toggle, light terminal (V11-09..11)
- [ ] 05-10-PLAN.md — Snapshot suite (every screen × state × default/XXL) + accessibility audits + contrast test (V11-11, V11-12)
- [ ] 05-11-PLAN.md — Remaining XCUITest flows + journey + flake gate; pre-release XcodeBuildMCP/impeccable review (V11-12)
- [ ] 05-12-PLAN.md — CHECKPOINT: 0.2.0 TestFlight upload, APNs key Sandbox & Production, on-device checklist + live Even Terminal safety check (V11-14)
**UI hint**: yes
