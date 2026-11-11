# Phase 1 Discussion Log (--auto)

[--auto] Selected all gray areas: repo/dev loop, runtime deps, spawn identity, event log & protocol, state model, hooks, process control, transcript, network, CLI client.

- [auto] Repo — Q: "Where does hub code live and how does it reach the PC?" → Selected: "Monorepo hub/ + private GitHub repo, PC pulls" (recommended)
- [auto] Dev loop — Q: "Develop on Mac or PC?" → Selected: "Cross-platform code, unit-test on Mac, on-PC spikes via swe" (recommended)
- [auto] Session id — Q: "How to map PTY session to transcript?" → Selected: "`claude --session-id <uuid>` + filename glob" (recommended, research-verified)
- [auto] Replay — Q: "Raw ring vs @xterm/headless?" → Selected: "Chunk ring + reset + resize nudge" (recommended, no dep)
- [auto] Term frames — Q: "Binary vs base64 JSON?" → Selected: "base64 in JSON for v1" (simpler single frame type)
- [auto] Hooks — Q: "http vs command hook?" → Selected: "type:http to loopback listener, command fallback" (recommended)
- [auto] Kill — Q: "Process-tree kill on Windows?" → Selected: "taskkill /T /F + boot sweep" (recommended)
- [auto] Network — Q: "Bind in phase 1?" → Selected: "127.0.0.1 only, no auth until Phase 2" (recommended, safe)
- [auto] Chat parsing — Q: "Hub-side chat events in Phase 1 or 3?" → Selected: "Phase 1 (hub side), UI in Phase 3"
- [auto] Client — Q: "How to verify without iOS?" → Selected: "Small cli.js (list/new/attach/send/interrupt/stop)"
