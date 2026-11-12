# Phase 5: v1.1 Safety, Chat and UI Rebuild - Context

**Gathered:** 2026-11-12
**Status:** Ready for planning
**Source:** Rishi's first on-device use of TestFlight 0.1.0 → `docs/v1.1-UPDATE.md` (read it first). User verdict: "app is pretty unusable right now", "looks vibe-coded", "hate the black background", "not smooth", wants "everything haptic, interactive, clean" + "really rigorous frontend testing".

<domain>
## Phase Boundary
Make echo safe around Even Terminal, make chat actually work for every session, and rebuild the UI to a polished, tested standard. Ship 0.2.0 to TestFlight.
</domain>

<decisions>
## Implementation Decisions

### Safety (P0-1) — never disturb Even Terminal
- **D-01:** Boot sweep already hardened (commit 7d2b569: kill only if cmdline contains the stored session id). Keep + add a test that `stop`/`killTree` can never target a non-hub pid.
- **D-02:** Global `~/.claude/settings.json` hooks stay **removed** (done 2026-11-12). External-session state + alerts come from the **transcript tailer** instead (assistant turn ends → `done`; idle detection), so echo touches nothing in Even Terminal's Claude config. Remove/disable the global-hook install from `install.sh` (keep code behind an explicit `--global-hooks` flag, default off).
- **D-03:** Take-over/Resume of a session whose entrypoint is `sdk-ts` (Even Terminal) or that any live process references (scan `ps` command lines for the id; `~/.claude/sessions/*.json`) → refuse with a clear message; no force path in v1.1.
- **D-04:** Diagnostic finding (netwatch, 2026-11-12): glasses drops are Even app SSE stream drops over Tailscale DERP relay on apartment Wi-Fi (client isolation), not echo. Keep `hub/tools/netwatch.sh`; echo app itself must tolerate relay latency (timeouts ≥ 10 s, graceful reconnect).

### Push (P0-2)
- **D-05:** Root cause `403 BadEnvironmentKeyInToken` = APNs key environment mismatch; Rishi must set the key to "Sandbox & Production" (human step in release checkpoint). Hub maps APNs reasons to plain-language errors returned to the app (`/devices/push/test` response + `/health.pushLastError`); Settings shows them verbatim-friendly.

### Chat & sessions (P1)
- **D-06:** `GET /sessions/:id/history?before=<cursor>&limit=200` (authed) returns chat lines parsed from the transcript for ANY session (hub-owned, stopped, exited, external) — works after hub restarts. App opens every session with full history, then live stream if available.
- **D-07:** External sessions: header "Watching — started in <label>" + primary **Continue here** button (take-over, guarded by D-03). Hub-owned sessions: composer always visible; verify send end-to-end in simulator against the live hub.
- **D-08:** Session list:
  - one-line summary per session: `ai-title` → first user prompt (trimmed) → last assistant line; ≤ 80 chars, computed hub-side (`summary` field in `/sessions`).
  - noise filter hub-side flags `noise: true` for entrypoint `sdk-cli`/`claude -p` one-shots, sessions with < 2 user turns, and externals idle > 7 days; app shows them under a collapsed "Other" section.
  - sort: active (running/waiting) first, then by last activity (add `lastActivity` from transcript mtime).
  - active vs inactive: distinct colour + subtle pulse for running, accent for waiting-for-you, muted for done/stopped/external.
- **D-09:** Zero-tap pairing: `POST /pair/auto` on the tailnet listener — succeeds only if whois LoginName == configured owner (and not tagged); returns a token. App tries it automatically on first launch / after 401; code pairing remains as fallback. Code field strips non-alphanumerics before the 8-char cap.

### UI rebuild (P2)
- **D-10:** Use the installed `impeccable` skill (critique → shape/polish → audit) and `swiftui-pro` review on every screen. Shared apothecary language stays (lavender canvas, cream paper, sage, serif display + rounded body). **No black surfaces**: terminal default theme is light paper/ink (dark terminal optional toggle).
- **D-11:** Motion: spring animations for navigation, list insert/remove/reorder, chip/state changes, composer; matched-geometry where natural; no layout jumps; respect Reduce Motion.
- **D-12:** Haptics: send, message/state arrival (light), pull-to-refresh, toggle, destructive confirm, errors (notification error), pairing success.
- **D-13:** Chat: bubbles with markdown, tool rows collapsed into a single expandable "used N tools" row, live "working…" indicator while running, jump-to-latest pill, designed empty/loading/error states.
- **D-14:** Accessibility: VoiceOver labels everywhere, Dynamic Type up to XXL without truncation of key info, contrast AA.

### Testing (rigorous)
- **D-15:** iOS 26 simulator runtime is now installed → move app UI verification to the simulator:
  - snapshot tests with pointfreeco/swift-snapshot-testing (test-only SPM dep, as WorkoutCoach does) for every screen × {light} × {default, XXL Dynamic Type} using fixture data (no network);
  - XCUITest flows against a deterministic **mock hub** (a tiny Node script reusing hub fixtures, started by the test plan on loopback) covering: auto-pair, list (summary, Other section), open stopped session shows history, send in hub-owned session, Continue here refusal message, Terminal toggle, push test error message;
  - XcodeBuildMCP screenshot review loop per screen before release (impeccable audit pass).
  - Hub: node:test additions for history endpoint, summary/noise/lastActivity, /pair/auto (owner/tagged/mismatch), D-03 guards, transcript-derived external state.
- **D-16:** Keep macOS `EchoR2Tests` for Core logic; app target tests run on an iPhone simulator.

### Release
- **D-17:** `ITSAppUsesNonExemptEncryption = NO`; bump to 0.2.0; release via `app/scripts/release.sh`; on-device checklist incl. push after key fix, auto-pair, history, Continue here, UI walkthrough.

### Claude's Discretion
Exact visual details within the design language (guided by impeccable), mock-hub shape, snapshot device list, noise thresholds tuning.
</decisions>

<canonical_refs>
- `docs/v1.1-UPDATE.md` — full issue list (P0–P3)
- `.planning/phases/04-push-recovery-release/*-SUMMARY.md`, `.planning/phases/03-ios-app/*-SUMMARY.md`
- `hub/*.js`, `hub/tools/netwatch.sh`, `app/**`, `app/scripts/release.sh`
- `/Users/rishizamvar/Documents/Projects/WorkoutCoach-iOS/project.yml` (SnapshotTesting usage pattern)
- impeccable skill, swiftui-pro skill, swift-concurrency skill
</canonical_refs>

<deferred>
- Approve/deny permission prompts from phone, Mac↔PC handoff, glasses switcher (v2)
- Parked PC plans (01-05, 01-06, 02-07)
</deferred>
