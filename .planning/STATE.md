# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-11)

**Core value:** From the phone, anywhere, Rishi can see what every Claude session on the home PC is doing and tell it what to do next, and gets pinged the moment one finishes or needs him.
**Current focus:** Phase 1: Hub Session Engine

## Current Position

Phase: 1 of 4 (Hub Session Engine)
Plan: Not started
Status: Ready to plan
Last activity: 2026-11-11 - Roadmap created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0

## Accumulated Context

### Decisions

- PC is the hub; phone talks only to PC
- Plain `ws://` over Tailscale (no cert code); verify ATS on device in Phase 3
- `type:"http"` loopback hooks, command-hook fallback (verify in Phase 1 spike)
- Chunk-boundary replay ring; `@xterm/headless` only if spike shows corruption

### Pending Todos

None yet.

### Blockers/Concerns

- All Windows/ConPTY behavior is unverified from the Mac; Phase 1 spikes must run on the PC
- Auto-logon for unattended reboot is Rishi's decision
- Pin phone whois login/node id; Tailscale ACL scoping

## Session Continuity

Last session: 2026-11-11
Stopped at: Roadmap created
Resume file: None
