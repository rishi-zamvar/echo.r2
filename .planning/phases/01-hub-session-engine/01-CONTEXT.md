# Phase 1: Hub Session Engine - Context

**Gathered:** 2026-11-11
**Status:** Ready for planning
**Mode:** --auto (recommended defaults selected; see 01-DISCUSSION-LOG.md)

<domain>
## Phase Boundary

A Node hub that spawns and supervises Claude Code sessions in ConPTY (node-pty), keeps them alive independent of clients, tracks live state from signals (PTY exit + Claude hooks), discovers external sessions from transcripts, emits a per-session seq-numbered event log (term + chat + state) with replay, and is driven end-to-end by a small CLI client. Loopback only in this phase — no Tailscale binding, pairing, autostart, or iOS (Phase 2/3).

Requirements: SESS-02, SESS-03, SESS-04, SESS-05. Hub-side endpoints that later phases consume (start session for SESS-01, chat events for CHAT-01..03) are built here too.

</domain>

<decisions>
## Implementation Decisions

### Repo & dev loop
- **D-01:** Monorepo `echo.r2/`: `hub/` (Node) now, `app/` (iOS) in Phase 3. Hub is a plain ESM package, no build step, no TypeScript.
- **D-02:** Hub code is cross-platform (node-pty works on macOS too). Develop and unit-test on the Mac; Windows-specific behavior is proven by on-PC spikes. Paths/commands branch on `process.platform` only where necessary (claude binary path, process-tree kill).
- **D-03:** Deploy to PC via a private GitHub repo (`rishi-zamvar/echo.r2`); PC clones/pulls. PC-side runs/spikes are delegated to the PC Claude (`swe`) via Dispatch with exact commands and expected output; results recorded in `01-SPIKES.md`.

### Runtime & deps
- **D-04:** Node 24 LTS. Runtime deps: `node-pty@1.1.0`, `ws@8.22.2` only. Everything else stdlib (`node:http`, `node:fs`, `node:crypto`, `node:test`).
- **D-05:** Target ~5–7 source files: `server.js` (HTTP + WS + routes), `sessions.js` (spawn/kill/input lock/state), `eventlog.js` (seq ring + replay), `transcript.js` (tailer + parser + external discovery), `hooks.js` (loopback receiver + settings merge), `store.js` (atomic JSON), `cli.js` (client). One test file `hub.test.js` (node:test).

### Session spawn & identity
- **D-06:** Hub generates a UUID and spawns `claude --session-id <uuid>`; hub session id == Claude session id. Transcript located by globbing `~/.claude/projects/*/<uuid>.jsonl` (never reverse-encode cwd).
- **D-07:** Spawn the real `claude` executable (resolve absolute path at startup; on Windows prefer `claude.exe`, not the `.cmd` shim). Spawn at 120x30, `name: xterm-256color`, explicit env passthrough. Never pass `--dangerously-skip-permissions`.
- **D-08:** Startup self-test: spawn `claude --version` via node-pty; log result; refuse to start sessions if it fails.

### Event log & wire protocol
- **D-09:** Per-session EventLog: one monotonic `seq` across kinds `term | chat | state`, plus `epoch` (hub boot id). Bounded ring by bytes (~2 MB term per session; chat/state small). Term chunks coalesced at ~16–50 ms and stored whole (never split mid-chunk).
- **D-10:** WS `GET /sessions/:id/stream?since=<seq>&epoch=<id>` replays from seq then streams live. If `since` predates the ring or epoch differs → send `{type:"reset"}`, replay what the ring has, and nudge a PTY resize to force Claude's TUI to repaint. `@xterm/headless` only if the spike shows corruption.
- **D-11:** Envelope: JSON text frames `{v:1, seq, kind, ...}`; term output as base64 in JSON for v1 (single frame type, simpler client). Client→hub frames: `{type:"input", text}`, `{type:"keys", data}` (raw), `{type:"resize", cols, rows}`, `{type:"interrupt"}`.
- **D-12:** REST: `GET /health`, `GET /sessions`, `POST /sessions {cwd, prompt?}`, `POST /sessions/:id/stop`. Protocol version in `/health`.

### State model
- **D-13:** States: `starting → running → waiting | done → running …`, terminal `exited`, `stopped` (hub restart), `external`. Driven only by: PTY data/exit, user input (→ running), `Stop` hook (→ done), `Notification` hook (→ waiting). Stop debounced per session (~1.5 s). One function owns transitions; unit-tested.

### Hooks
- **D-14:** Use Claude Code `type: "http"` hooks POSTing to a **separate loopback listener** `127.0.0.1:<hookPort>` with a shared secret (header if supported, else secret path segment). Fallback if the PC spike shows http hooks unsupported: command hook `node <abs>/hook.js` (exit 0, 2 s timeout).
- **D-15:** Hook installer merges into `~/.claude/settings.json` (backup first, marker comment/key for idempotent uninstall), never overwrites. Hooks fire for all PC sessions: unknown `session_id` → `external` record.
- **D-16:** Hook receiver returns 200 immediately, processes async; validates payload shape.

### Process control & writers
- **D-17:** Stop = Windows `taskkill /PID <pid> /T /F`; POSIX `process.kill(-pid)` / tree kill. Store PIDs; on hub boot, sweep stale stored PIDs and mark their sessions `stopped`.
- **D-18:** Interrupt = write `\x03` to the PTY.
- **D-19:** Input lock: per-session serialized write queue; text input written as bracketed paste then `\r`. External sessions refuse input with an error frame.

### Transcript & chat (hub side)
- **D-20:** Tailer: byte offsets per file, buffer partial last line, `fs.watch` + 1 s stat-poll fallback. Parse whitelist `user`/`assistant` lines; content blocks `text` → message, `tool_use` → one-line summary (`tool name + short arg`), `tool_result` → skipped or ok/err badge; ignore `thinking` and unknown types.
- **D-21:** External discovery: transcripts modified in the last N minutes not owned by the hub → `external`, labeled by `entrypoint` (`sdk-ts` → "Even Terminal/SDK", `cli` → "Terminal"). Title from `ai-title`/`last-prompt` lines when present.

### Network (phase 1 only)
- **D-22:** Phase 1 binds `127.0.0.1` only (app port 8790, hook port 8791; env-overridable). No auth in Phase 1 because loopback-only; Phase 2 adds Tailscale bind + whois + token before any non-loopback exposure.

### CLI client
- **D-23:** `node cli.js list | new <cwd> [prompt] | attach <id> [--since n] | send <id> <text> | interrupt <id> | stop <id>`. `attach` pipes term output to the local terminal (raw mode) — this is the Phase 1 acceptance driver.

### Claude's Discretion
- Exact ring sizes, coalescing interval, debounce values, file split within the ~5–7 file budget, log format.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project
- `.planning/PROJECT.md` — scope, constraints, key decisions
- `.planning/REQUIREMENTS.md` — SESS-02..05 (+ hub side of SESS-01, CHAT-01..03)
- `.planning/ROADMAP.md` §Phase 1 — success criteria + on-PC spike list
- `docs/superpowers/specs/2026-11-11-echo-r2-v1-design.md` — approved design

### Research
- `.planning/research/SUMMARY.md` — reconciled decisions (transport, replay, hooks, kill)
- `.planning/research/ARCHITECTURE.md` — transcript format, hook payloads, `--session-id`
- `.planning/research/PITFALLS.md` — ConPTY, orphan trees, two writers, hooks
- `.planning/research/STACK.md` — versions, stdlib choices

### External docs
- https://code.claude.com/docs/en/hooks — hook types (incl. `http`), payloads
- https://github.com/microsoft/node-pty — ConPTY API

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None in this repo (greenfield). Old ZeeChat artifacts in `legacy-reference/` are reference only (Dispatch chat shim, ping scripts) — do not reuse.
- Even Terminal (`~/.npm-global/lib/node_modules/@evenrealities/even-terminal/`) is a working example of node-pty + Claude Agent SDK on the same machine class; read-only reference for spawn/env handling.

### Established Patterns
- Ponytail: stdlib first, minimal deps, fewest files, one runnable test file.

### Integration Points
- `~/.claude/projects/**/<uuid>.jsonl` (transcripts), `~/.claude/settings.json` (hooks), `claude` CLI on PATH.
- Dispatch (`dispatchctl send swe ...`) for PC-side spike execution.

</code_context>

<specifics>
## Specific Ideas

- Rishi often drives from Even Realities G2 glasses; hub logs and CLI output should be terse.
- PC is Windows, Claude Code native install, Tailscale node `zee-cloud`.

</specifics>

<deferred>
## Deferred Ideas

- Tailscale bind, whois, pairing, autostart, install/deploy scripts → Phase 2
- iOS app, chat/terminal UI → Phase 3
- APNs, resume/take-over UI, TestFlight → Phase 4
- Permission approve/deny from phone, Mac↔PC handoff, glasses switcher → v2

</deferred>
