# Phase 2 Discussion Log (--auto)

User decision (live): PC down ~1 month → Mac is the real stand-in hub (launchd).

[--auto] Selected all gray areas: binding, whois, pairing/tokens, revoke, cwd allowlist, health, Mac autostart, Windows autostart, global hooks, deploy, logs.

- [auto] Binding — "How does the local CLI reach the hub once it's on tailnet?" → "Separate unauthenticated loopback listener + authenticated tailnet listener" (recommended)
- [auto] Identity — "whois source?" → "`tailscale whois --json` CLI, 60 s cache, owner pinned" (recommended)
- [auto] Pairing — "Code format?" → "8-char base32, single-use, 5 min, 5 tries" (recommended)
- [auto] Token transport — "Header or query?" → "Authorization header only" (recommended)
- [auto] Health — "Auth on /health?" → "whois only, no token" (lets unpaired app find hub)
- [auto] Mac autostart — "launchd agent vs login item?" → "LaunchAgent RunAtLoad+KeepAlive" (recommended)
- [auto] Mac sleep — "Prevent sleep?" → "No; documented caveat" (simplest)
- [auto] Windows — "Write now or later?" → "Write now, verify when PC returns" (matches user decision)
- [auto] External alerts — "Global hooks now?" → "Yes, marked merge into settings.json with backup + uninstall" (needed for EXT state)
- [auto] Deploy — "How?" → "git pull + npm ci + restart + SHA health check"
