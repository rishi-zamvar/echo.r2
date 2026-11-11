# Walking Skeleton — echo.r2

**Phase:** 1
**Generated:** 2026-11-11

## Capability Proven End-to-End

From a CLI on the hub machine, Rishi starts a real Claude Code session in the hub (`node hub/cli.js new <cwd> "<prompt>"`), attaches and watches its live TUI, detaches, and re-attaches with `--since <seq>` to get exactly the output he missed while the session kept running.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Runtime | Node 24 LTS (PC), Node >=22 accepted for Mac dev; plain ESM (`"type":"module"`), no TypeScript, no build step | D-01, D-04; node-pty is N-API so one prebuild covers 22/24 |
| Runtime deps | `node-pty@1.1.0`, `ws@8.22.2` (exact pins, lockfile committed). Nothing else. | D-04, ponytail |
| PTY | node-pty `spawn(claudePath, ['--session-id', id, '--settings', hooksFile, prompt?], {name:'xterm-256color', cols:120, rows:30, cwd, env: scrubbedEnv})` | D-06, D-07, D-15, D-15a |
| Session identity | Hub `crypto.randomUUID()` == Claude session id (`--session-id`) | D-06 |
| Transport | One `http.Server` on `127.0.0.1:8790` (REST + WS upgrade via `ws` `noServer`); separate hook listener `127.0.0.1:8791` | D-12, D-14, D-22 |
| Wire protocol v1 | JSON text frames only. Hub→client: `{v:1,type:'hello',id,epoch,seq,state}`, `{v:1,type:'reset',epoch}`, `{v:1,type:'error',code}`, events `{v:1,seq,kind:'term',data:<base64>}` / `{v:1,seq,kind:'state',state}` / `{v:1,seq,kind:'chat',role,text,tool?}`. Client→hub: `{type:'input',text}`, `{type:'keys',data}`, `{type:'resize',cols,rows}`, `{type:'interrupt'}` | D-11 |
| Replay | Per-session `EventLog` ring (2 MB cap), one monotonic `seq` across kinds, hub `epoch` = boot UUID. `?since=<seq>&epoch=<id>`; stale since/epoch → `reset` + full ring + resize nudge | D-09, D-10 |
| Data layer | `store.js` atomic JSON (`write tmp` + `fs.renameSync`) at `$ECHO_DATA_DIR/sessions.json` (default `~/.echo-hub`) | STACK.md; no SQLite |
| State signals | PTY data/exit, user input, `Stop`/`Notification` http hooks; one pure `transition(state, signal)` | D-13 |
| Auth | None in Phase 1; loopback bind only. Hook listener requires per-boot `X-Echo-Secret`. Phase 2 adds Tailscale bind + whois + bearer token BEFORE any non-loopback bind | D-22 |
| Test | ONE file `hub/hub.test.js` (`node:test`), fake claude at `hub/fixtures/fake-claude.mjs` injected via `startHub({claudeCmd})` | D-05, research harness |
| Directory layout | `hub/{server,sessions,eventlog,transcript,hooks,store,cli}.js`, `hub/hub.test.js`, `hub/fixtures/`, `hub/spikes/` (PC spike aids, not runtime) | D-05 |
| Deployment | Private GitHub repo `rishi-zamvar/echo.r2`; PC clones/pulls and runs `npm ci` + `node server.js`; PC work delegated to `swe` via Dispatch | D-03 |

## Stack Touched in Phase 1

- [x] Project scaffold — `hub/package.json`, exact-pinned deps, `node --test hub/hub.test.js`
- [x] Routing — `GET /health`, `GET /sessions`, `POST /sessions`, `POST /sessions/:id/stop`, WS `/sessions/:id/stream`
- [x] Data — `sessions.json` written on every session create/state change, read at boot
- [x] Interactive client — `cli.js attach` (raw-mode keystrokes in, TUI bytes out)
- [x] Run target — local full-stack command `node hub/server.js` + `node hub/cli.js ...`; PC run via git pull

## Out of Scope (Deferred to Later Slices)

- Tailscale bind, whois, bearer token, pairing, `/health` git SHA, autostart, install/deploy scripts, global `~/.claude/settings.json` hook merge (Phase 2)
- iOS app, project allowlist UI (Phase 3)
- APNs, `--resume`, take-over (Phase 4)
- `@xterm/headless` server-side screen model (only if PC spike shows replay corruption)
- Binary WS frames (base64-in-JSON for v1)

## Subsequent Slice Plan

- Phase 2: hub reachable only by the paired phone over Tailscale, running unattended at PC login
- Phase 3: iOS app pairs, lists, starts, chats, and opens the terminal against this protocol
- Phase 4: push alerts, resume after hub restart, take-over, TestFlight
