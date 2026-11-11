# Phase 1: Hub Session Engine - Research

**Researched:** 2026-11-11
**Domain:** Node hub supervising Claude Code TUI sessions via node-pty (ConPTY on Windows), event log + WS replay, Claude hooks, transcript tailing
**Confidence:** HIGH on Mac-verifiable items (node-pty, hooks over HTTP, bracketed paste, kill, transcripts). MEDIUM on Windows (not testable from the Mac; covered by the spike script below).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Monorepo `echo.r2/`: `hub/` (Node) now, `app/` (iOS) in Phase 3. Hub is a plain ESM package, no build step, no TypeScript.
- **D-02:** Hub code is cross-platform (node-pty works on macOS too). Develop and unit-test on the Mac; Windows-specific behavior is proven by on-PC spikes. Paths/commands branch on `process.platform` only where necessary (claude binary path, process-tree kill).
- **D-03:** Deploy to PC via a private GitHub repo (`rishi-zamvar/echo.r2`); PC clones/pulls. PC-side runs/spikes are delegated to the PC Claude (`swe`) via Dispatch with exact commands and expected output; results recorded in `01-SPIKES.md`.
- **D-04:** Node 24 LTS. Runtime deps: `node-pty@1.1.0`, `ws@8.22.2` only. Everything else stdlib (`node:http`, `node:fs`, `node:crypto`, `node:test`).
- **D-05:** Target ~5-7 source files: `server.js`, `sessions.js`, `eventlog.js`, `transcript.js`, `hooks.js`, `store.js`, `cli.js`. One test file `hub.test.js` (node:test).
- **D-06:** Hub generates a UUID and spawns `claude --session-id <uuid>`; hub session id == Claude session id. Transcript located by globbing `~/.claude/projects/*/<uuid>.jsonl` (never reverse-encode cwd).
- **D-07:** Spawn the real `claude` executable (resolve absolute path at startup; on Windows prefer `claude.exe`, not the `.cmd` shim). Spawn at 120x30, `name: xterm-256color`, explicit env passthrough. Never pass `--dangerously-skip-permissions`.
- **D-08:** Startup self-test: spawn `claude --version` via node-pty; log result; refuse to start sessions if it fails.
- **D-09:** Per-session EventLog: one monotonic `seq` across kinds `term | chat | state`, plus `epoch` (hub boot id). Bounded ring by bytes (~2 MB term per session; chat/state small). Term chunks coalesced at ~16-50 ms and stored whole (never split mid-chunk).
- **D-10:** WS `GET /sessions/:id/stream?since=<seq>&epoch=<id>` replays from seq then streams live. If `since` predates the ring or epoch differs -> send `{type:"reset"}`, replay what the ring has, and nudge a PTY resize to force Claude's TUI to repaint. `@xterm/headless` only if the spike shows corruption.
- **D-11:** Envelope: JSON text frames `{v:1, seq, kind, ...}`; term output as base64 in JSON for v1. Client->hub frames: `{type:"input", text}`, `{type:"keys", data}` (raw), `{type:"resize", cols, rows}`, `{type:"interrupt"}`.
- **D-12:** REST: `GET /health`, `GET /sessions`, `POST /sessions {cwd, prompt?}`, `POST /sessions/:id/stop`. Protocol version in `/health`.
- **D-13:** States: `starting -> running -> waiting | done -> running ...`, terminal `exited`, `stopped` (hub restart), `external`. Driven only by: PTY data/exit, user input (-> running), `Stop` hook (-> done), `Notification` hook (-> waiting). Stop debounced per session (~1.5 s). One function owns transitions; unit-tested.
- **D-14:** Use Claude Code `type: "http"` hooks POSTing to a **separate loopback listener** `127.0.0.1:<hookPort>` with a shared secret (header if supported, else secret path segment). Fallback if the PC spike shows http hooks unsupported: command hook `node <abs>/hook.js` (exit 0, 2 s timeout).
- **D-15:** Hook installer merges into `~/.claude/settings.json` (backup first, marker comment/key for idempotent uninstall), never overwrites. Hooks fire for all PC sessions: unknown `session_id` -> `external` record.
- **D-16:** Hook receiver returns 200 immediately, processes async; validates payload shape.
- **D-17:** Stop = Windows `taskkill /PID <pid> /T /F`; POSIX `process.kill(-pid)` / tree kill. Store PIDs; on hub boot, sweep stale stored PIDs and mark their sessions `stopped`.
- **D-18:** Interrupt = write `\x03` to the PTY.
- **D-19:** Input lock: per-session serialized write queue; text input written as bracketed paste then `\r`. External sessions refuse input with an error frame.
- **D-20:** Tailer: byte offsets per file, buffer partial last line, `fs.watch` + 1 s stat-poll fallback. Parse whitelist `user`/`assistant` lines; content blocks `text` -> message, `tool_use` -> one-line summary, `tool_result` -> skipped or ok/err badge; ignore `thinking` and unknown types.
- **D-21:** External discovery: transcripts modified in the last N minutes not owned by the hub -> `external`, labeled by `entrypoint` (`sdk-ts` -> "Even Terminal/SDK", `cli` -> "Terminal"). Title from `ai-title`/`last-prompt` lines when present.
- **D-22:** Phase 1 binds `127.0.0.1` only (app port 8790, hook port 8791; env-overridable). No auth in Phase 1.
- **D-23:** `node cli.js list | new <cwd> [prompt] | attach <id> [--since n] | send <id> <text> | interrupt <id> | stop <id>`. `attach` pipes term output to the local terminal (raw mode) - the Phase 1 acceptance driver.

### Claude's Discretion
Exact ring sizes, coalescing interval, debounce values, file split within the ~5-7 file budget, log format.

### Deferred Ideas (OUT OF SCOPE)
- Tailscale bind, whois, pairing, autostart, install/deploy scripts -> Phase 2
- iOS app, chat/terminal UI -> Phase 3
- APNs, resume/take-over UI, TestFlight -> Phase 4
- Permission approve/deny from phone, Mac<->PC handoff, glasses switcher -> v2
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SESS-02 | See all sessions with live state: running, waiting, done, exited, stopped, external | Hook payloads (Stop/Notification) verified; `~/.claude/sessions/<pid>.json` liveness registry; transcript discovery + `entrypoint` values; state fn design |
| SESS-03 | Sessions keep running when client disconnects | PTYs owned by hub process, not WS; event ring + `since` replay; ws heartbeat/backpressure |
| SESS-04 | Interrupt (Ctrl-C) or stop; stop kills whole tree | `\x03` verified to reach TUI; POSIX `kill(-pid)` verified no orphans; Windows `taskkill /T /F` + node-pty kill internals |
| SESS-05 | One writer per session; external read-only | Per-session promise-chain write queue; bracketed-paste+CR sequence verified; external refusal |
</phase_requirements>

## Summary

Everything the hub needs from Claude Code was verified live on this Mac with the installed Claude 2.1.322 and node-pty 1.1.0: `--session-id <uuid>` is honored (hook `session_id` and transcript filename both equal it), `type:"http"` hooks work with a custom header whose value is interpolated from an env var (`headers` + `allowedEnvVars`), bracketed paste followed by `\r` submits a prompt to the TUI, and killing the PTY's process group leaves no orphans on POSIX. The tarball ships prebuilds for win32-x64, win32-arm64, darwin-arm64, darwin-x64 and uses node-addon-api (N-API), so no per-Node-version rebuild is needed; node-pty's `install` script only compiles if the `prebuilds/<platform>-<arch>` dir is missing.

Three real gotchas surfaced that are not in prior research: (1) the darwin `spawn-helper` prebuild is shipped non-executable, so first spawn fails with `posix_spawnp failed` until `chmod +x`; (2) if the hub's own environment contains `CLAUDE_*` variables (any time it is launched from inside a Claude session), spawned Claude shows "Transcript saving is off - inherited CLAUDE_CODE_CHILD_SESSION marker", which would silently kill the chat/transcript feature; the hub must scrub `CLAUDE*` env vars; (3) a brand-new cwd triggers the "trust this folder" dialog (and first-run dialogs), which swallows pasted input and defaults to "No, exit". The hub needs an allowlist of already-trusted dirs or a `starting`-state timeout, and should pass the first prompt as the CLI positional `[prompt]` arg rather than pasting.

One recommendation tensions with D-15: Claude has `--settings <file-or-json>`, which merges extra settings (including hooks) for that process only. Verified working. For hub-owned sessions this removes the settings.json-snapshot concern, the backup/merge risk, and lets the secret live in the child env. D-15's settings.json merge is still required to see *external* sessions' hooks (and can be deferred to Phase 2 install if the planner wants; transcript tailing already discovers externals).

**Primary recommendation:** Spawn with `claude --session-id <uuid> --settings <hub-generated hooks.json> [prompt]` in a scrubbed env; keep D-15 installer as a separate, optional function for external-session hooks; verify Windows behavior with the spike script in section "On-PC Spike Script".

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Spawn/supervise Claude PTY | Hub (Node process) | OS (ConPTY/pty) | Hub owns child lifetime; independent of clients |
| Event log + replay | Hub | - | Single seq source of truth; clients are stateless |
| State machine | Hub | Claude hooks (signal source) | Driven by hooks + PTY exit, never by screen scraping |
| Chat parsing | Hub (transcript tailer) | Claude (writes JSONL) | Transcript is durable source; PTY text unparseable |
| Process-tree kill | Hub | OS (`taskkill`/pgrp) | Only hub knows PIDs |
| Input serialization | Hub | - | One writer per PTY |
| Terminal rendering | CLI client (Phase 1), iOS later | - | Hub streams raw bytes |
| Auth | none in Phase 1 (loopback) | - | D-22 |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| node-pty | 1.1.0 (published; npm registry) | PTY/ConPTY spawn | Microsoft-maintained; locked by D-04 |
| ws | 8.22.2 | WebSocket server sharing `http.Server` | Locked by D-04; zero deps |
| Node.js | 24 LTS target (D-04) | Runtime | Mac dev box currently has v22.20.0; both work since node-pty is N-API |

### Alternatives Considered
None (locked). Do not add xterm-headless unless spike shows replay corruption (D-10).

**Installation:**
```bash
cd hub && npm init -y && npm i node-pty@1.1.0 ws@8.22.2
# macOS only (and in a startup helper): chmod +x node_modules/node-pty/prebuilds/darwin-*/spawn-helper
```

**Version verification:** `npm view node-pty@1.1.0` -> deps `{node-addon-api:^7.1.0}`, `install: node scripts/prebuild.js || node-gyp rebuild`, `postinstall: node scripts/post-install.js` (only cleans `build/Release`; local, no network). `npm view ws@8.22.2` OK, no postinstall. [VERIFIED: npm registry + tarball inspection]

## Package Legitimacy Audit

slopcheck could not be installed (no `pip` on this Mac), so per protocol both packages are `[ASSUMED]` for the gate. Mitigation: both are user-locked (D-04), node-pty maintainers on npm include `microsoft1es` / `alexr00@microsoft.com`, ws repo is `github.com/websockets/ws`; tarball for node-pty was downloaded and inspected (postinstall reads no network).

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| node-pty | npm | years (microsoft) | high | github.com/microsoft/node-pty | unavailable | Approved (locked D-04, [ASSUMED] by protocol) |
| ws | npm | 10+ yrs | very high | github.com/websockets/ws | unavailable | Approved (locked D-04, [ASSUMED] by protocol) |

**Packages removed:** none. **Packages flagged [SUS]:** none. Planner: a one-line human-verify on first `npm i` is sufficient given the lock.

## Architecture Patterns

### System Architecture Diagram

```
 CLI client (attach/send/stop)                      Claude Code (in PTY)
        |  REST + WS  (127.0.0.1:8790)                 |  |  \
        v                                              |  |   \ writes
 +----------------- HUB (one Node process) ------------|--|----\--------------+
 | server.js: http.Server --upgrade--> ws (noServer)   |  |     v             |
 |    routes -> sessions.js                             |  | ~/.claude/projects|
 |                                                      |  |   /*/<uuid>.jsonl |
 | sessions.js: spawn(claude --session-id U --settings H)  |        |          |
 |    pty.onData --coalesce 16-50ms--> eventlog.append(term)       |          |
 |    write queue (1 writer) --> pty.write                         v          |
 |    state(sig) <-- PTY exit / input / hook events      transcript.js tailer |
 |                                                       (offset,fs.watch+poll)|
 | eventlog.js: seq++ ring(bytes) -> fan-out to ws clients <-- chat events     |
 |                                                                             |
 | hooks.js: http.Server 127.0.0.1:8791  <---- HTTP POST (Stop/Notification) --+
 |    check X-Echo-Secret, 200 now, process async -> sessions.state()          |
 | store.js: sessions.json (atomic tmp+rename; pids, cwd, epoch)               |
 +-----------------------------------------------------------------------------+
 Stop: win32 taskkill /PID p /T /F ; posix process.kill(-p,'SIGKILL')
```

### Recommended Project Structure
```
hub/
  package.json         # "type":"module"
  server.js            # http + ws upgrade + routes + main()
  sessions.js          # spawn, kill, write queue, state fn, claude path resolve, env scrub
  eventlog.js          # seq ring + replay + coalescer
  transcript.js        # tailer, line parser, external discovery
  hooks.js             # loopback listener + hooks.json generator + optional settings.json merge
  store.js             # atomic JSON
  cli.js               # client
  hub.test.js          # node:test, uses ../.planning/.../fixtures/transcript-sample.jsonl copy
```
Copy the fixture to `hub/fixtures/transcript-sample.jsonl` when building (it lives in the phase dir now).

### Pattern 1: node-pty spawn (verified)
```js
// node-pty 1.1.0 typings (typings/node-pty.d.ts) + live test on darwin-arm64
import pty from 'node-pty';
const env = Object.fromEntries(Object.entries(process.env).filter(([k, v]) => v != null && !/^CLAUDE/i.test(k)));
const p = pty.spawn(claudePath, ['--session-id', id, '--settings', hooksFile /*, prompt*/], {
  name: 'xterm-256color', cols: 120, rows: 30, cwd, env: { ...env, ECHO_SECRET: secret },
});
p.onData(d => /* string, utf8 */ ..);   // IEvent<string>
p.onExit(({ exitCode, signal }) => ..);
p.write(str); p.resize(cols, rows); p.pid;
p.kill(signal?) // POSIX: process.kill(pid, signal||'SIGHUP'), swallows errors. Windows: THROWS if a signal arg is given.
```
- API surface: `onData`, `onExit({exitCode, signal})`, `write`, `resize`, `pause/resume`, `clear`, `kill`, `pid`; options `name, cols, rows, cwd, env, encoding, handleFlowControl, useConpty, useConptyDll(experimental, default false), conptyInheritCursor`. [VERIFIED: tarball typings/node-pty.d.ts]
- `onData` is string-decoded UTF-8 by default. Chunks can end mid-multibyte-sequence only if `encoding:null` (Buffer mode); leave default.
- POSIX: node-pty forks with `setsid`, so `pty.pid` is a process-group leader: `process.kill(-pid,'SIGKILL')` killed shell and its background child; `pgrep` showed no orphan. [VERIFIED: live test]
- Windows: `kill()` closes ConPTY and `process.kill`s every pid from the console process list (windowsPtyAgent.js). Still follow D-17 with `taskkill /PID <pid> /T /F` as belt-and-braces; spike confirms which pid (`pty.pid`) is right. [VERIFIED: source; behaviour needs PC spike]

### Pattern 2: hooks via `--settings` file + http type (verified live)
```json
{ "hooks": {
  "Stop":         [{ "hooks": [{ "type":"http", "url":"http://127.0.0.1:8791/hook/Stop",
      "headers": { "X-Echo-Secret": "$ECHO_SECRET" }, "allowedEnvVars": ["ECHO_SECRET"], "timeout": 5 }] }],
  "Notification": [{ "hooks": [{ "type":"http", "url":"http://127.0.0.1:8791/hook/Notification", "headers": {"X-Echo-Secret":"$ECHO_SECRET"}, "allowedEnvVars":["ECHO_SECRET"], "timeout": 5 }] }],
  "SubagentStop": [ ...same shape... ]
}}
```
Live result: Stop POST arrived with `content-type: application/json`, header `x-echo-secret: s3cret` (interpolated from the child's env), body:
```json
{"session_id":"<uuid==--session-id>","transcript_path":"/Users/.../.claude/projects/-Users-...-Projects/<uuid>.jsonl","cwd":"...","scratchpad_dir":"...","prompt_id":"...","permission_mode":"auto","effort":{"level":"medium"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"pong","background_tasks":[],"session_crons":[]}
```
[VERIFIED: live test, Claude 2.1.322] Schema per docs: common fields `session_id, transcript_path, cwd, hook_event_name, permission_mode, prompt_id, agent_id/agent_type (in subagent)`; Notification adds `message`, optional `title`, `notification_type` (`permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`, `elicitation_*`, ...); SubagentStop adds `stop_hook_active`, `agent_id`, `agent_type`, `last_assistant_message`. [CITED: code.claude.com/docs/en/hooks]
- Failure semantics: non-2xx / connection failure is a non-blocking error by default (`onFailure:"continue"`, v2.1.295+); response must be empty 2xx (or valid JSON object). So `res.writeHead(200); res.end()` is correct and a down hub never stalls Claude. [CITED: docs]
- Did NOT observe: Notification (no permission prompt occurred in the test; verify in spike), `SessionStart` over http (a SessionStart http hook defined in `--settings` did not reach the listener at startup; docs say some hook types are skipped at launch). Do not depend on SessionStart. [VERIFIED: negative observation, single run; LOW-MEDIUM]
- Snapshot question: official docs say direct edits to settings hooks are "normally picked up automatically by the file watcher" [CITED]; third-party posts claim mid-session edits are not reliably picked up [LOW]. With `--settings` per spawn the question is moot for hub sessions; for the D-15 merge, install before any session starts and treat already-running sessions as not covered.
- Hub-owned vs external in hooks: because `--settings` hooks fire only for hub sessions, a hook for an unknown `session_id` only occurs if D-15's global merge is installed.

### Pattern 3: ws 8 on a shared http.Server
```js
import { WebSocketServer } from 'ws';
const wss = new WebSocketServer({ noServer: true });
server.on('upgrade', (req, sock, head) => {
  const u = new URL(req.url, 'http://x'); const m = u.pathname.match(/^\/sessions\/([\w-]+)\/stream$/);
  if (!m) return sock.destroy();
  wss.handleUpgrade(req, sock, head, ws => attach(ws, m[1], u.searchParams));
});
// heartbeat (ws README pattern)
const iv = setInterval(() => { for (const ws of wss.clients) { if (ws.isAlive === false) { ws.terminate(); continue; } ws.isAlive = false; ws.ping(); } }, 20000);
// on connection: ws.isAlive = true; ws.on('pong', () => ws.isAlive = true);
// backpressure: before ws.send(frame): if (ws.bufferedAmount > 1<<20) ws.terminate();  // client reconnects with since=
```
[CITED: ws README heartbeat pattern, local node_modules/ws/README.md; backpressure policy is a recommendation] Dropping a slow client is safe because replay-by-seq makes reconnect lossless (within the ring).

### Pattern 4: Bracketed paste + submit (verified live)
Write `'\x1b[200~' + text + '\x1b[201~'`, wait, then write `'\r'` as a separate write. Live test: paste of a 2-line text then `\r` 1 s later -> Claude replied "pong"; the Stop hook fired. Use a short delay (>= 50-100 ms; test used 1000 ms) between paste end and `\r`, inside the same serialized write-queue entry, so another writer cannot interleave. Ctrl-C (`\x03`) at an idle prompt did not exit the TUI (needs double press), so `interrupt` is safe to send repeatedly. Multi-line text must be pasted (not typed) so embedded `\n` do not submit. [VERIFIED: live test]

### Pattern 5: Write queue (SESS-05)
```js
// per-session promise chain; no lib
s.q = s.q.then(async () => { s.pty.write('\x1b[200~' + text + '\x1b[201~'); await sleep(80); s.pty.write('\r'); });
// raw "keys"/interrupt frames also go through s.q so they never land inside a paste
// external: reject immediately with {type:'error', code:'read_only'}
```

### Pattern 6: Event log (D-09/D-10)
Ring entries `{seq, kind, t, bytes, payload}`; track `bytes` total, shift oldest while over cap; floor = `ring[0].seq`. Replay: if `epoch !== hub.epoch || since < floor-1` -> send `{type:'reset'}` first, then everything in the ring, then call `pty.resize(cols, rows+1)` then `resize(cols, rows)` after ~50 ms to force a repaint. Coalesce with a 16-50 ms timer per session that flushes the accumulated string as one term event (base64 of utf8). Never split chunks.

### Pattern 7: Transcript discovery and liveness
- Hub-owned: poll/`fs.watch` the projects root, match basename `<uuid>.jsonl`; prefer `transcript_path` from the first hook. In this Claude version the file exists essentially at session start (it contained `mode`, `permission-mode`, `last-prompt` lines before the first prompt); older research said "only after first prompt", so spike-confirm on the PC and still tolerate absence. [VERIFIED on Mac]
- **New finding:** `~/.claude/sessions/<pid>.json` is a live-session registry written by Claude: `{pid, sessionId, cwd, startedAt, procStart, version, kind, entrypoint, ...}`. A pid-alive check on these gives a far better external-session liveness signal than mtime. Undocumented, so treat as optional with mtime fallback; spike whether it exists on Windows. [VERIFIED on Mac; undocumented -> MEDIUM]
- `entrypoint` values observed across 2900 local lines: `cli` (interactive terminal), `sdk-ts` (SDK/Even-style), `claude-desktop`, `sdk-cli`. Map unknown values to "Other".
- Transcript lines can be huge (a 520 KB file in a 1-turn session due to `api-request-blob`/`attachment` lines): read by byte offset in chunks, split on `\n` in Buffer space (decode only whole lines) so multibyte chars are not split, and skip `JSON.parse` for non-whitelisted types cheaply by checking the prefix is not needed; just parse and ignore.
- `user` lines: `message.content` is either a plain **string** (typed prompt) or an array (tool_result / text blocks, e.g. `[Request interrupted by user]`). `assistant` lines are one block per line, same `message.id`/`requestId`. `is_error` appears on `tool_result` blocks. Fixture: `fixtures/transcript-sample.jsonl` (synthetic but shape-faithful; includes string and array user content, thinking, text, tool_use, tool_result, unknown type, unicode, `ai-title`, `last-prompt`, `system`).
- Skip user lines whose string content starts with `<local-command`, `<command-name>`, or has `isMeta:true` (slash-command noise seen in real files).

### Anti-Patterns to Avoid
- **Passing the hub's full env to Claude:** triggers "Transcript saving is off" when `CLAUDE_CODE_CHILD_SESSION` is inherited. Scrub `^CLAUDE`.
- **Typing the first prompt blindly right after spawn:** first-run/trust dialogs eat it. Use positional `[prompt]`.
- **Trusting `pty.kill()` alone on POSIX:** sends SIGHUP to one pid only; use the process group.
- **Reverse-encoding cwd to find transcripts** (D-06 already says so).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UUID | uuid pkg | `crypto.randomUUID()` | stdlib |
| Hook transport | curl/bash hooks | `type:"http"` + `headers`/`allowedEnvVars` | verified working; no shell on Windows |
| Settings injection for hub sessions | edit `~/.claude/settings.json` | `claude --settings <file>` | per-process, no backup/merge/snapshot problems |
| WS keepalive | custom framing | ws `ping()` + `pong` | built in |
| Atomic JSON | lib | write tmp + `fs.renameSync` | stdlib |
| ANSI stripping in tests | lib | one regex (see test harness) | only for assertions |

## Runtime State Inventory
Not a rename/refactor phase. Skipped.

## Common Pitfalls

### Pitfall 1: darwin `spawn-helper` not executable
**What goes wrong:** `Error: posix_spawnp failed.` on first `pty.spawn` on macOS. **Why:** tarball file mode is 0644 for `prebuilds/darwin-*/spawn-helper`. **Avoid:** at startup on non-win32, `fs.chmodSync(<node-pty>/prebuilds/<platform>-<arch>/spawn-helper, 0o755)` wrapped in try; also fixes after `npm ci`. **Warning:** failure is immediate and obvious. [VERIFIED: reproduced + fixed]

### Pitfall 2: Inherited `CLAUDE_*` env disables transcripts
See Anti-Patterns. Scrub `^CLAUDE` (includes `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_ENTRYPOINT`). Keep `ANTHROPIC_*`/auth vars. On the PC under Task Scheduler this will not occur, but dev on the Mac inside Claude will. [VERIFIED]

### Pitfall 3: Trust dialog / first-run dialogs block the TUI
A cwd Claude has never seen shows "Is this a project you trust?" with default "No, exit"; Enter exits Claude (exit code 1) - observed. `POST /sessions` should (a) pass prompt as positional arg, (b) keep state `starting` until a hook or transcript line appears, (c) surface a `starting` timeout (e.g. 20 s -> state event `needs_attention`/stay `starting` and log), (d) Phase 3's allowlist should only contain pre-trusted dirs. Do not auto-accept trust.

### Pitfall 4: Hub launched from inside Claude holds the hook port
Port 8791 in use between dev runs; make listener `EADDRINUSE` fatal with a clear message.

### Pitfall 5: Double events / duplicate replay
Assign `seq` at append time only, and send the live frame and replay from the same ring so a client that attaches mid-flush cannot see a gap or duplicate: snapshot `since`-slice and register the client synchronously in the same tick.

### Pitfall 6: Stop hook fires per turn, and subagents
Stop -> `done` debounced 1.5 s; `SubagentStop` must NOT drive session state (it has `agent_id`; ignore events with `agent_id` for state). A user input arriving during debounce cancels it.

### Pitfall 7: ConPTY specifics (Windows, needs spike)
`env` must not contain `undefined` values; resize before first data can be dropped; `kill(signal)` throws on Windows; cwd must exist. Console-list agent forks a helper (`conpty_console_list_agent`), so a hung child can delay `kill()`; rely on taskkill.

### Pitfall 8: Orphans after hub crash
Hub crash leaves `claude` running (PTY dies with parent on POSIX; on Windows ConPTY children may survive). D-17 sweep on boot: for stored pids, if alive and image name matches `claude`, kill tree, mark `stopped`.

## Code Examples

### Process-tree kill
```js
import { execFile } from 'node:child_process';
function killTree(pid) {
  if (process.platform === 'win32') execFile('taskkill', ['/PID', String(pid), '/T', '/F'], () => {});
  else { try { process.kill(-pid, 'SIGKILL'); } catch {} }   // verified no orphan on macOS
}
```

### Hook receiver
```js
http.createServer((q, r) => {
  let b = ''; q.on('data', d => { b += d; if (b.length > 1e6) q.destroy(); });
  q.on('end', () => {
    const ok = q.method === 'POST' && q.headers['x-echo-secret'] === SECRET;
    r.writeHead(ok ? 200 : 403).end();                 // always fast
    if (ok) queueMicrotask(() => { try { onHook(JSON.parse(b)); } catch {} });
  });
}).listen(HOOK_PORT, '127.0.0.1');
```
Use `crypto.timingSafeEqual` if desired; loopback-only so plain compare is acceptable (ponytail).

### Transcript tail core
```js
// per file: {off, rest:Buffer}
const fd = fs.openSync(f,'r'); const n = fs.fstatSync(fd).size;
if (n < off) off = 0;                       // truncated/rotated
const buf = Buffer.alloc(n-off); fs.readSync(fd, buf, 0, n-off, off); fs.closeSync(fd);
let data = Buffer.concat([rest, buf]); off = n;
const i = data.lastIndexOf(10); rest = data.subarray(i+1);
for (const line of data.subarray(0, i+1).toString('utf8').split('\n')) if (line) try { parse(JSON.parse(line)) } catch {}
```
Call on `fs.watch` event and on a 1 s `setInterval` stat check.

### Test harness trick
Unit-test `sessions.js` with a fake "claude": a tiny `node -e` script spawned through node-pty that echoes input, so SESS-03/04/05 are testable on the Mac without API calls. Make `claudePath`/args injectable (env `ECHO_CLAUDE_CMD`).

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Command hook + curl | `type:"http"` hook with `headers`+`allowedEnvVars` (`onFailure` since v2.1.295) | No shell dependency on Windows |
| Edit global settings.json | `claude --settings <file-or-json>` | Per-process hooks |
| Liveness by mtime | `~/.claude/sessions/<pid>.json` registry (undocumented) | Better external liveness |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Windows native `claude.exe` lives at `%USERPROFILE%\.local\bin\claude.exe` (or on PATH) | Spike | Spawn fails; spike S1 resolves it |
| A2 | On Windows `pty.pid` is the right pid for `taskkill /T` (vs `innerPid`) | Kill | Orphans; spike S4 checks |
| A3 | `~/.claude/sessions/<pid>.json` exists with same shape on Windows | Pattern 7 | Fall back to mtime heuristic |
| A4 | Notification http hook fires on permission prompt with `notification_type` | Pattern 2 | `waiting` state never set; spike S5 |
| A5 | http hooks defined in `--settings` behave identically on Windows | Pattern 2 | Fall back to D-14 command hook; spike S5 |
| A6 | Windows transcript is created at session start like on Mac | Pattern 7 | Chat empty until first prompt; tolerate |
| A7 | slopcheck-unavailable packages are fine (locked by D-04) | Audit | Negligible |
| A8 | Tools listed in `dir` of `[prompt]` positional arg starts the session submitting the prompt | Pitfall 3 | Fall back to paste after Stop/idle; verify Mac smoke (not run here) |

## Open Questions (RESOLVED)

Resolution: Q1 → verified by 01-01 Task 4 Mac smoke; Q2 → adopted as CONTEXT D-15 (revised); Q3 → not relevant to Phase 1. Command-hook fallback (D-14) and interrupt→state behavior are routed via spike results and `/gsd:plan-phase 1 --gaps` if the PC shows divergence.

1. **Does `[prompt]` positional start the TUI with the prompt auto-submitted?** Not tested here (cost-free to test on Mac smoke). Recommendation: plan a Mac smoke task; fallback is paste after transcript file appears.
2. **D-15 vs `--settings`:** needs planner/user acknowledgement that hub-owned sessions use `--settings` and global merge becomes optional (external sessions only). Recommend adopting; D-14's secret-via-header is satisfied by env interpolation.
3. **SessionStart http hook not delivered at startup** (single observation). Irrelevant to design; do not use.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node (Mac) | dev/test | yes | 22.20.0 (target 24) | N-API so OK; `nvm`/fnm for 24 if wanted |
| claude CLI (Mac) | smoke | yes | 2.1.322 | fake-claude in tests |
| npm | install | yes | - | - |
| pip/slopcheck | audit | no | - | marked ASSUMED |
| PC: Node 24, claude, git | spikes | unknown | - | via Dispatch to `swe` |

## Validation Architecture

(`workflow.nyquist_validation` is false in config; included because the request explicitly asked.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `node:test` + `node:assert` (stdlib) |
| Config file | none |
| Quick run | `node --test hub/hub.test.js` |
| Full suite | same (single file) + `node hub/cli.js` smoke |

### Success Criterion -> Verification
| # | Criterion | Mechanism | Where |
|---|-----------|-----------|-------|
| SC1a | Session outlives client | hub.test: start fake-claude session via sessions.js, open WS, close it, assert pty still alive and `onData` keeps appending to the ring | unit (Mac) |
| SC1b | Reconnect `since=<seq>` returns missed output, no dup | hub.test: append N events, connect with `since=k`, assert frames are exactly seq k+1..N, strictly increasing, no repeats; `since < floor` -> `reset` first; epoch mismatch -> `reset` | unit |
| SC1c | Real Claude survives CLI disconnect | `node cli.js new <trusted-cwd> "say hi"`, `attach`, Ctrl-], re-`attach --since n` | Mac CLI smoke, then PC spike S2 |
| SC2a | State transitions | hub.test: pure `transition(state, signal)` table incl. Stop debounce, input cancels debounce, SubagentStop ignored, exit -> exited, boot sweep -> stopped, unknown hook sid -> external | unit |
| SC2b | Hooks drive state | hub.test: POST sample Stop/Notification bodies (from this doc) to hook listener with/without secret; assert 200/403 and state change | unit |
| SC2c | Hooks from real Claude (http type, header interpolation) | on Mac already verified; repeat on PC | PC spike S5 |
| SC2d | External discovery + label | hub.test: temp projects dir with fixture copies (`entrypoint` cli / sdk-ts) -> list shows `external` with labels and `ai-title` | unit |
| SC3a | Interrupt reaches process | hub.test: fake-claude (node script reading raw stdin) records `\x03`; real: `cli interrupt` then see "Interrupted" in attach | unit + Mac smoke + PC S3 |
| SC3b | Stop kills whole tree | hub.test (POSIX): fake-claude spawns a grandchild `sleep`; after `stop`, `process.kill(pid,0)` throws for both. Windows: PC spike S4 with `tasklist` | unit (Mac) + PC S4 |
| SC4a | Serialized input from two clients | hub.test: two concurrent `input` sends with long text; fake-claude echoes bytes; assert pasted blocks are contiguous (no interleave) | unit |
| SC4b | External refused | hub.test: `input` on external session returns `error/read_only`, nothing written | unit |
| Parser | Transcript | hub.test: fixture -> expected chat events (user text, assistant text, tool_use summary "Bash: ls -la", tool_result badge ok, thinking/unknown/system dropped, partial last line buffered then completed) | unit |

### Sampling Rate
- Per task commit: `node --test hub/hub.test.js`
- Per wave: same + Mac CLI smoke with real claude (one cheap prompt)
- Phase gate: unit green, Mac smoke green, `01-SPIKES.md` has S1-S7 results

### Wave 0 Gaps
- [ ] `hub/hub.test.js`, `hub/fixtures/transcript-sample.jsonl` (copy from phase dir)
- [ ] fake-claude script (inline in test via `node -e` or a 15-line fixture file) with injectable command
- [ ] `npm i node-pty@1.1.0 ws@8.22.2` + spawn-helper chmod

## Security Domain

Phase 1 is loopback-only with no auth (D-22). Controls still needed:

| ASVS | Applies | Control |
|------|---------|---------|
| V5 Input validation | yes | Validate `cwd` exists and is a directory, `id` matches UUID regex, JSON frame shape; cap body size (1 MB), WS message size (`maxPayload`) |
| V2/V3/V4 | no (Phase 2) | Bind 127.0.0.1 explicitly, never 0.0.0.0 |
| V6 Crypto | no | secret = `crypto.randomBytes(16).toString('hex')` per boot, passed via child env only |

| Threat | STRIDE | Mitigation |
|--------|--------|------------|
| Local process posts fake hooks | Spoofing | `X-Echo-Secret` check (403 otherwise) |
| Arbitrary cwd/command via POST /sessions | Elevation | command is fixed `claude`; only `cwd`+`prompt` taken; prompt passed as argv element (no shell); Phase 2/3 adds allowlist |
| Secret leakage in logs | Info disclosure | never log env or hook headers |
| `--dangerously-skip-permissions` | Elevation | never pass (D-07) |

## On-PC Spike Script (for `swe` via Dispatch)

Preconditions on PC: `git clone` private repo, `cd echo.r2\hub`, `npm ci` (or `npm i node-pty@1.1.0 ws@8.22.2`), Node 24. Record all results in `.planning/phases/01-hub-session-engine/01-SPIKES.md`. Run in a normal interactive PowerShell **and** repeat S1/S4 once from a Task Scheduler-launched shell (`schtasks /create /tn echoSpike /sc once /st 23:59 /tr "powershell -File C:\path\spike.ps1"` then `/run`) for the claude.exe PATH question.

**S1 - prebuild + claude resolution**
```powershell
node -v; node -p "process.platform+'-'+process.arch"
Test-Path node_modules\node-pty\prebuilds\win32-x64\conpty.node; Test-Path node_modules\node-pty\build   # expect True / False (no compile)
where.exe claude; claude --version; Get-Command claude | Format-List Source
Test-Path $env:USERPROFILE\.local\bin\claude.exe
node -e "const p=require('node-pty').spawn(process.argv[1],['--version'],{name:'xterm-256color',cols:120,rows:30,cwd:process.cwd(),env:process.env});p.onData(d=>process.stdout.write(d));p.onExit(e=>console.log('exit',e))" (where.exe claude | Select -First 1)
```
Report: node version, whether a native compile ran, absolute claude path, whether `.cmd` vs `.exe`, `--version` output through the PTY, and whether it also works from the scheduled-task shell.

**S2 - TUI under ConPTY** (use a small script `spike-tui.mjs`, same pattern as the Mac test: spawn `claude --session-id <uuid> --settings hooks.json` in an already-trusted cwd, scrubbed env). Steps and what to report:
1. Dump first 1.5 s of raw output (JSON.stringify, first 600 chars) - did TUI draw? any dialogs (trust, first-run)?
2. `write('\x1b[200~say pong\x1b[201~')`, 500 ms, `write('\r')` -> did Claude answer "pong"? (also try a paste with a newline inside).
3. Arrow keys `\x1b[A \x1b[B`, UTF-8 string `naïve café 日本語` echoed in input line (report raw bytes seen).
4. `resize(100,40)` then `resize(120,30)`: did output reflow/repaint?
5. `write('\x03')` while a long answer is generating ("count from 1 to 200 slowly"): did it interrupt?
6. Replay/repaint test: capture all output into a string, start a fresh `@xterm/headless`-free comparison: simply report whether after `resize(cols,rows+1)`+`resize(cols,rows)` the TUI re-emits a full screen (bytes received within 500 ms).

**S3/S4 - orphan check after tree kill**
```powershell
# after S2 session is running with pid P (print p.pid and innerPid if present)
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'claude|node|conhost|OpenConsole' } | Select ProcessId,ParentProcessId,Name | Format-Table
taskkill /PID <P> /T /F
Start-Sleep 2
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'claude' } | Select ProcessId,Name
```
Report: is `pty.pid` the claude pid or conhost/agent; list of descendants before; any `claude.exe` left after; also test `pty.kill()` alone and report leftovers; test with a child that spawns a Bash tool (`!sleep`-style prompt: ask Claude to run `ping -n 120 127.0.0.1`) and report if `ping.exe` survives taskkill.

**S5 - hooks**
`claude --version`; run S2 with `--settings hooks.json` (http hooks, header `X-Echo-Secret: $ECHO_SECRET`, `allowedEnvVars`) against a listener (`node -e` http server on 127.0.0.1:8791 printing method, url, headers, body). Report: Stop body verbatim (redact paths if needed), whether header interpolated, whether SessionStart fired. Then trigger a permission prompt (ask Claude to run a command that needs approval with `permission_mode` default, e.g. cwd with no allow rules: "run `echo hi > x.txt`") and report the Notification body (`notification_type`, `message`). Trigger a subagent ("use the Explore agent to list files") and report SubagentStop body. If http hooks do not fire: repeat with a `command` hook `{"type":"command","command":"node","args":["C:\\...\\hook.js"],"timeout":2}` and report.

**S6 - transcripts**
```powershell
Get-ChildItem $env:USERPROFILE\.claude\projects -Directory | Select Name -First 5   # report encoding of a dir for e.g. C:\Users\X\proj
Get-ChildItem $env:USERPROFILE\.claude\projects\*\<uuid>.jsonl
Get-ChildItem $env:USERPROFILE\.claude\sessions | Select -First 3; Get-Content (first .json)
```
Report: encoded dir name, whether `<uuid>.jsonl` exists before the first prompt, `entrypoint` of the hub session (`cli`?) and of an Even Terminal session if one exists, whether `~/.claude/sessions/<pid>.json` exists.

**S7 - fixture**: copy 12-15 lines of a real PC transcript, sanitize paths/content, report as `fixtures/transcript-pc.jsonl`; verify partial-line handling by reading it while a session is mid-answer (note any lines >100 KB).

## Sources

### Primary (HIGH)
- Live experiments on this Mac (node-pty 1.1.0 spawn, process-group kill, Claude 2.1.322 with `--session-id`, `--settings`, http hook, bracketed paste)
- npm tarball `node-pty-1.1.0.tgz`: `prebuilds/`, `scripts/prebuild.js`, `typings/node-pty.d.ts`, `lib/windowsPtyAgent.js`, `lib/unixTerminal.js`
- https://code.claude.com/docs/en/hooks (http hook fields, payloads, onFailure, Windows notes)
- `claude --help` (2.1.322): `--session-id`, `--settings`, `[prompt]`

### Secondary (MEDIUM)
- ws README heartbeat pattern (local node_modules)
- Local transcript inspection (~2900 lines for `entrypoint` values)

### Tertiary (LOW)
- Third-party claims that hooks edits mid-session are not reloaded (contradicted by official doc wording)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (locked + verified install/spawn)
- Architecture: HIGH on Mac, MEDIUM on Windows
- Pitfalls: HIGH (three reproduced live)

**Side effect disclosure:** during live Claude tests I accidentally accepted a first-run dialog; `~/.claude/settings.json` mtime changed (it already had `permissions.defaultMode: "auto"` so content likely unchanged) and `~/.claude.json` was updated by Claude normally. The test transcript was deleted.

**Research date:** 2026-11-11
**Valid until:** ~2026-12-11 (Claude Code CLI moves fast; recheck hook options on the PC's installed version)
