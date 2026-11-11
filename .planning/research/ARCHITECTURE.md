# Architecture Patterns

**Domain:** Phone-to-PC hub controlling Claude Code CLI sessions (echo.r2)
**Researched:** 2026-11-11
**Overall confidence:** MEDIUM-HIGH (transcript format and hooks verified locally and in official docs; Windows-specific path encoding and ConPTY behaviour not testable from the Mac)

## Recommended Architecture

One Node process (the hub) owns everything. The hub is the only writer to PTYs and the only component that talks to APNs. The phone is a thin client over one WebSocket plus a small REST surface.

```
                    Tailscale (WSS + bearer token + whois)
 iPhone app  <------------------------------------------->  HUB (Node, Windows)
  SwiftUI                                                    |
  SwiftTerm                                                  |-- http/ws server  (bound to Tailscale IP)
                                                             |-- auth            (whois + token, pairing)
                                                             |-- SessionManager  (id, cwd, state, PTY)
                                                             |     `-- node-pty -> `claude --session-id <uuid>`
                                                             |-- EventLog        (per-session seq ring + replay)
                                                             |-- TranscriptTailer(~/.claude/projects/**.jsonl)
                                                             |-- HookReceiver    (127.0.0.1 only)
                                                             |-- Notifier        (APNs .p8)
                                                             `-- Store           (JSON/SQLite)
 Claude Code (in PTY) --HTTP hook POST (Stop, Notification)--> HookReceiver (loopback)
 Even Terminal / plain claude --writes--> ~/.claude/projects/*.jsonl --> TranscriptTailer (watch-only)
```

### Component Boundaries

| Component | Responsibility | Talks to |
|-----------|---------------|----------|
| Server + Auth | Bind Tailscale IP; check whois + bearer; pairing code exchange; REST + WS upgrade | App, SessionManager, EventLog |
| SessionManager | Spawn/kill/resume PTYs; track state (running, waiting, done, exited, stopped, external); write input; resize | node-pty, EventLog, Store |
| EventLog | Per-session monotonic `seq`; bounded ring of events (term bytes, chat messages, state changes); replay `since=seq` then live fan-out | SessionManager, TranscriptTailer, WS clients |
| TranscriptTailer | Watch `~/.claude/projects/*/*.jsonl`; incremental read by byte offset; parse lines into chat events; discover external sessions | EventLog, SessionManager |
| HookReceiver | Loopback-only endpoint; Stop/Notification -> state transition + push | SessionManager, Notifier |
| Notifier | APNs JWT (.p8), send, retry once, drop token on 410 | Store |
| Store | sessions, device tokens, APNs tokens | all |
| iOS Connection layer | One WS, auto-reconnect, tracks last seq per session, banner state | Views |
| iOS Chat view | Renders chat events | Connection |
| iOS Terminal view | SwiftTerm fed raw bytes; sends keys/resize | Connection |

Keep this in about 5-7 hub files (server, sessions, transcript, hooks, apns, store, test), not one-class-per-box.

### Data Flow

1. Start: `POST /sessions {cwd, prompt?}` -> hub generates `uuid`, spawns `claude --session-id <uuid>` in ConPTY with cwd, returns `uuid`. Hub session id == Claude session id. No discovery step needed.
2. Terminal path: PTY `onData` -> EventLog (kind=term, seq++) -> WS clients. Input: WS `{type:"input"}` or raw keys -> `pty.write`. Resize -> `pty.resize`.
3. Chat path: transcript file for that session is tailed -> parsed -> EventLog (kind=chat, seq++) -> WS. Chat is derived from the file, never from PTY text.
4. Alerts: Claude hook (HTTP POST to loopback) -> HookReceiver -> state change event + APNs push -> tap deep-links to session id.
5. Reconnect: client sends `since=<lastSeq>`; hub replays from ring; if `since` is older than ring floor, hub sends a `reset` event and the client re-syncs (chat: re-read transcript from start; term: replay scrollback snapshot).

Direction: Claude/PTY/transcript -> hub -> phone for output; phone -> hub -> PTY for input. Hooks flow Claude -> hub only.

## Verified specifics

### Transcript JSONL format (HIGH, inspected a real file locally, Claude Code with `sdk-ts` entrypoint)
- Location: `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`. One file per session; subagents go in `<session-id>/subagents/`. Encoded cwd replaces non-alphanumeric characters with `-` (`/Users/x/Documents/Projects` -> `-Users-x-Documents-Projects`). On Windows expect `C:\Users\x` -> `C--Users-x` (MEDIUM: not verified on Windows; do not rely on it, see below).
- Append-only, one JSON object per line. Observed `type` values: `user`, `assistant`, `system`, `attachment`, `queue-operation`, `ai-title`, `last-prompt`, `mode`, `tools-used`, `cost-state`, `api-request*`, `atis-latch`. The set is undocumented and drifts between versions: the parser MUST ignore unknown types.
- Chat-relevant lines are only `user` and `assistant`. Each has `sessionId`, `uuid`, `parentUuid`, `timestamp`, `cwd`, `isSidechain`, `entrypoint`, `version`, `message`.
- `message.content` is a list of blocks: `text`, `thinking`, `tool_use`, `tool_result` (user lines carrying a `tool_result` are tool output, not human input). Assistant text arrives as separate lines per block (one line per content block, same `requestId`), so do not assume one line = one turn.
- `ai-title` line gives an auto session title (use for the list); `last-prompt` gives the last user prompt (use as subtitle).
- `entrypoint` distinguishes origin: observed `sdk-ts` for Agent-SDK-driven sessions (this is what Even Terminal uses); interactive CLI sessions should show `cli` (MEDIUM, not directly observed). Use it to label "external (Even)" vs "external (terminal)".
- Flush is asynchronous; official docs say `transcript_path` "may lag the current turn". So Stop hook payload's `last_assistant_message` is the source for push text, not the file.

### Mapping a PTY session to its transcript (HIGH)
- `claude --session-id <uuid>` exists in current CLI help ("Use a specific session ID for the conversation", must be a valid UUID). Hub pre-generates the uuid, so the transcript is `<uuid>.jsonl` in the project dir for that cwd.
- Do not compute the directory by encoding cwd. Instead watch `~/.claude/projects/*/<uuid>.jsonl` (glob by filename); file appears after first message, so poll/`fs.watch` the projects root and match by basename. Hook payloads also carry `session_id` and `transcript_path` explicitly; record `transcript_path` from the first hook and prefer it.
- Caveat: the file is not created until the first prompt is processed; an idle fresh session has no transcript. Chat view shows empty state until then.
- Caveat to test on PC: `claude --resume <id>` may keep the same id or create a new one depending on version (`--fork-session` flag exists, implying default keeps the id). On resume, re-key by what the first hook or new file reports.

### Hooks on Windows (HIGH from official docs, https://code.claude.com/docs/en/hooks)
- Stop and Notification hooks receive JSON including `session_id`, `transcript_path`, `cwd`, `hook_event_name`. Stop additionally has `last_assistant_message`. Notification has `message` and `notification_type` (`permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_completed`, ...).
- Use the `type: "http"` handler. It POSTs the event body directly to a URL, so no bash/PowerShell script, no Git Bash dependency, no quoting problems on Windows. This removes the main Windows risk.
```json
{ "hooks": {
  "Stop":         [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:PORT/hook", "timeout": 5 }] }],
  "Notification": [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:PORT/hook", "timeout": 5 }] }]
}}
```
- Put it in `~/.claude/settings.json` (user scope, merges with project hooks, does not replace them). Hub must merge into the existing file, not overwrite it, and be idempotent on startup.
- Hooks fire for ALL sessions on the PC, including Even Terminal and plain terminal ones. This is a feature: external sessions also get pushes. Hub keys by `session_id`; unknown id -> create an `external` session record.
- Loopback hook endpoint is separate from the Tailscale-bound API (different listener on 127.0.0.1), so no bearer token is required there. Any local process can POST to it; acceptable for a single-user PC, but validate shape and rate-limit.
- Hook timeout default is 600s, so set a short one and always respond 200 immediately; do push work after responding. A slow or down hub must never stall Claude.
- Stop vs "waiting for you": Stop = turn finished (state `done`/idle). Notification with `permission_prompt`/`idle_prompt` = needs you. Map both to state `waiting`. `stop_hook_active` was not confirmed in docs read; do not return exit code 2.

### `claude --resume` (HIGH for flags, MEDIUM for semantics)
- `-r, --resume [value]` resumes by session id; `-c, --continue` most recent in cwd; `--fork-session` creates a new id on resume. Take-over = spawn `claude --resume <id>` in the PC cwd recorded in the transcript's `cwd` field (resume is cwd-scoped to the project dir, so the cwd must match). Restart-recovery uses the same call.
- Two writers on one session file corrupt the thread. Hub should refuse take-over while an external process is detected as live (transcript mtime within last N seconds is a cheap heuristic) unless the user confirms.

### How Even Terminal sessions appear on disk (MEDIUM)
- Same directory and file layout as any session; Agent SDK sessions are indistinguishable except `entrypoint: "sdk-ts"` (confirmed from a local SDK-driven file). No Even-specific marker was found; there is no liveness signal on disk beyond file mtime and hooks. External = transcript file the hub did not spawn. Liveness: `mtime` recency plus last hook seen.
- Even Terminal 0.10.x specifics (session naming, whether it sets a cwd you can resume in) were not verified from its package. Flag for hands-on check on the PC.

## Patterns to Follow

### Pattern 1: Single sequenced event log per session
**What:** Everything the phone sees is an event `{seq, kind, ...}` in one ring buffer per session (kinds: `term`, `chat`, `state`). Replay = send events with `seq > since`.
**When:** Always. This satisfies seq replay for both views with one mechanism.
**Example:**
```js
const ev = { seq: ++s.seq, kind: 'term', data: chunk.toString('base64') };
s.ring.push(ev); if (s.ring.length > MAX) s.ring.shift();
for (const ws of s.clients) ws.send(JSON.stringify(ev));
// replay: s.ring.filter(e => e.seq > since); if (since < s.ring[0]?.seq - 1) send({kind:'reset'})
```
Term events should be coalesced (e.g., 16-50ms) before assigning seq, to avoid thousands of tiny events. Chat events are small; the transcript is the durable source so chat ring can be rebuilt from file.

### Pattern 2: Tail by byte offset, parse whole lines only
Keep `offset` per file; on change read from offset, split on `\n`, keep trailing partial line buffered. Use `fs.watch` plus a 1-2s poll fallback (Windows watch events can coalesce or drop). On hub start, scan existing files once to build the session list (read only head/tail for `ai-title`, `cwd`), do not replay history into the ring.

### Pattern 3: Hub session id == Claude session id
Pre-generate the uuid and use `--session-id`. Removes all heuristics for correlating PTY to file, hook, and push.

### Pattern 4: State machine from signals, not screen scraping
`running` on input sent; `waiting` on Stop/Notification hook; `exited` on PTY exit; `stopped` on hub restart; `external` for non-hub files. Never parse PTY text for state.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Building chat from PTY output
**Why bad:** ANSI/TUI redraws make text unparseable. **Instead:** transcript JSONL only.

### Anti-Pattern 2: Strict schema on transcript lines
**Why bad:** Undocumented, many type changes per release (`api-request`, `atis-latch` exist today). **Instead:** whitelist `user`/`assistant`, tolerate everything else, add a one-file fixture test from a real transcript.

### Anti-Pattern 3: Shell-script hooks on Windows
**Why bad:** bash vs PowerShell default depends on Git Bash presence, quoting, `.cmd` shim rules. **Instead:** `type: "http"` hooks.

### Anti-Pattern 4: Overwriting `~/.claude/settings.json`
**Why bad:** destroys the user's other hooks/permissions. **Instead:** read, merge, write back atomically, tag our entries by URL for idempotence.

### Anti-Pattern 5: Unbounded buffers / one event per PTY chunk
**Instead:** ring bounded by bytes, coalesce, `reset` on gap.

### Anti-Pattern 6: Hub trusting hook payload for the only copy of state
Hooks can be missed (hub down). On startup and on WS connect, reconcile state from file mtime and PTY liveness.

## Scalability Considerations

Single user, a handful of sessions; scaling is a non-goal.

| Concern | Realistic load (1 user, <10 sessions) | Note |
|---------|------------------|------|
| Ring memory | ~1-2 MB per session cap | cap by bytes |
| File watching | Watch projects root recursively; poll fallback | Windows recursive watch is supported by `fs.watch` |
| Push volume | A few per hour | One retry; collapse by session via `apns-collapse-id` |

## Suggested Build Order

Dependencies drive order. De-risk the PC-specific unknowns (ConPTY, Windows hook/path behaviour) first, and make the hub testable with a CLI/`websocat` client before any iOS UI exists.

1. **Hub core: PTY + event log + WS (no auth yet, loopback)** - spawn `claude --session-id`, stream term events, input, resize, seq replay. Smoke on the PC. Highest technical risk (node-pty on Windows with Claude's TUI), so first. Deliverable: replay unit test.
2. **Transcript tailer + chat events + session list** - find `<uuid>.jsonl`, parse, derive title/state, discover external sessions (entrypoint tag). Fixture test from a real transcript. Depends on 1 for hub-owned id mapping.
3. **Hook receiver + state machine** - install HTTP hooks (merge), loopback listener, Stop/Notification -> state. Verify on Windows that HTTP hooks fire. Depends on 1-2.
4. **Auth + pairing + Tailscale binding** - whois check, per-device token, one-time pairing code. Wrap the already-working endpoints; kept after core so dev is not blocked, but must land before any exposure beyond loopback and before the app talks to it.
5. **iOS app skeleton + connection layer** - XcodeGen, DesignSystem import, pairing screen, WS with reconnect/seq, ConnectionBanner, sessions list. Unit test for decode and seq logic.
6. **Session detail: Chat view, then Terminal view (SwiftTerm), new-session flow** - chat first (cheaper, validates the event stream), terminal second.
7. **APNs + notifications** - .p8 sender, device token registration, deep link, 410 cleanup. Needs TestFlight/device build, so sits late; hub side can be unit-tested earlier against sandbox.
8. **Resume/take-over + restart recovery + Task Scheduler autostart** - `claude --resume`, stopped state, external warnings. Depends on all above; small once state model exists.

Parallelism: steps 1-4 (hub) and 5 (iOS skeleton against a mock/replay hub) can proceed in parallel after the wire protocol (event shape, REST routes) is fixed in step 1.

## Roadmap Research Flags

- Phase 1 (PTY): needs a hands-on PC spike: node-pty prebuilds for the installed Node version, Claude TUI under ConPTY, resize, keystrokes (Ctrl-C, arrows), UTF-8.
- Phase 3 (hooks): verify on PC that `type: "http"` hooks are honoured by the installed Claude version (feature is recent; confirm version on PC with `claude --version`) and that hook posts to 127.0.0.1 work. Fallback: `command` hook with `node -e`/`powershell.exe` exec form.
- Phase 8 (resume): verify whether `--resume` keeps the same session id on the PC's version and how Even Terminal ids/cwd behave.
- Phase 4: Tailscale whois from Node on Windows: use LocalAPI (named pipe on Windows) or `tailscale whois --json <ip>`; spike it, as the Windows LocalAPI transport differs from Unix socket.
- Phase 7: standard APNs patterns, low research need.

## Sources

- Local inspection of `~/.claude/projects/*/*.jsonl` and `claude --help` on the Mac (HIGH for format and flags on this version; Windows unverified).
- Claude Code hooks reference: https://code.claude.com/docs/en/hooks (HIGH; fetched 2026-11-11, first ~100k of 293k chars read, Stop/Notification/http/Windows sections covered).
- Project spec: `/Users/rishizamvar/Documents/Projects/echo.r2/docs/superpowers/specs/2026-11-11-echo-r2-v1-design.md`.
- Not verified: Even Terminal package internals; node-pty/ConPTY behaviour with Claude TUI; Windows project-dir encoding.
