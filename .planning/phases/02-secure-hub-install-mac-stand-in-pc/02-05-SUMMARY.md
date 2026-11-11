---
phase: 02-secure-hub-install-mac-stand-in-pc
plan: 05
subsystem: hub-install
tags: [windows, powershell, task-scheduler, firewall, UNVERIFIED]
requires: [02-03, 02-04]
provides: [windows install/uninstall/deploy scripts]
key-files:
  created:
    - hub/install/install.ps1
    - hub/install/uninstall.ps1
    - hub/install/deploy.ps1
decisions:
  - "Windows scripts mirror install.sh/deploy.sh output lines; hooks via shared hooks-merge.js"
metrics:
  tasks: 2
  files: 3
  completed: 2026-11-11
---

# Phase 2 Plan 05: Windows install/uninstall/deploy Summary

PowerShell 5.1 scripts for Task Scheduler autostart (At log on, restart 1 min x999, hidden, interactive/limited), a tailnet-only firewall rule (TCP 8790 from 100.64.0.0/10), hooks merge via the shared hooks-merge.js, and a deploy that confirms the new gitSha via /health. **UNVERIFIED: no PowerShell on the Mac; static review only. 02-07 must run them on the PC.**

## Commits
- fb4ff60: install.ps1 + uninstall.ps1
- 8e468d7: deploy.ps1

## Static checks
All acceptance greps pass (required cmdlets present; no `??`, `&&`, `0.0.0.0`, 8791, `-Password`).

## ASSUMED items for 02-07 to confirm
- Hidden launch via `powershell.exe -WindowStyle Hidden -Command "& 'node' 'server.js'; exit $LASTEXITCODE"`; a console flash may occur and the task's `-WorkingDirectory` is honored.
- `New-ScheduledTaskSettingsSet` params: `-RestartCount/-RestartInterval/-ExecutionTimeLimit ([TimeSpan]::Zero)/-AllowStartIfOnBatteries/-DontStopIfGoingOnBatteries/-MultipleInstances IgnoreNew/-StartWhenAvailable`.
- `New-ScheduledTaskTrigger -AtLogOn -User DOMAIN\USER`, `New-ScheduledTaskPrincipal -UserId ... -LogonType Interactive -RunLevel Limited`, `Register-ScheduledTask -Force` (idempotent re-run) without a stored password.
- `New-NetFirewallRule` with `-RemoteAddress 100.64.0.0/10 -Profile Any`; `Get-NetFirewallRule -DisplayName ... | Remove-NetFirewallRule` when the rule is absent is silent.
- `claude` and `node.exe` visible on the PATH the interactive task inherits.
- `git -C ... rev-parse` failure inside try/catch under `$ErrorActionPreference='Stop'` sets `$LASTEXITCODE` (PS 5.1 native-stderr behavior).
- `Get-CimInstance Win32_Process` CommandLine match on `server.js` + hub path kills only the hub node process.
- `Invoke-RestMethod` health response exposes `.gitSha`.

## Deviations from Plan
None. (Minor: deploy.ps1 uses try/catch instead of `2>$null` for the git toplevel check, to avoid PS 5.1 stderr-redirect terminating errors under Stop.)

## Known Stubs
None.

## Self-Check: PASSED
Files exist; commits fb4ff60 and 8e468d7 in git log.
