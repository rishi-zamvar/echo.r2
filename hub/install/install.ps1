# UNVERIFIED on Windows until plan 02-07 (PC down). Run from an elevated PowerShell.
# Registers the echo-hub logon task, the tailnet-only firewall rule, and the Claude hooks.
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Error 'run from an elevated PowerShell (firewall rule needs admin)'; exit 1 }

$hub = Split-Path -Parent $PSScriptRoot
$node = (Get-Command node.exe -ErrorAction Stop).Source
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Error 'claude not found on PATH'; exit 1 }
$user = "$env:USERDOMAIN\$env:USERNAME"

Push-Location $hub
npm ci --omit=dev
if ($LASTEXITCODE) { Pop-Location; exit 1 }
Pop-Location

& $node "$hub\install\hooks-merge.js" merge
if ($LASTEXITCODE) { exit 1 }

# Hidden launch via powershell.exe; a brief console flash is possible (UNVERIFIED).
$arg = "-NoProfile -WindowStyle Hidden -Command `"& '$node' '$hub\server.js'; exit `$LASTEXITCODE`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $hub
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName echo-hub -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

# Second wall behind the tailnet-only bind: inbound 8790 from Tailscale CGNAT range only.
Get-NetFirewallRule -DisplayName echo-hub -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName echo-hub -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8790 -RemoteAddress 100.64.0.0/10 -Profile Any | Out-Null

Start-ScheduledTask -TaskName echo-hub
for ($i = 0; $i -lt 20; $i++) {
  try {
    $h = Invoke-RestMethod -Uri 'http://127.0.0.1:8790/health' -TimeoutSec 2
    Write-Output "installed $($h.gitSha)"
    Write-Output 'next: node hub\cli.js pair <name>; disable Tailscale key expiry for this machine'
    exit 0
  } catch { Start-Sleep -Seconds 1 }
}
Write-Error "install FAILED (see $env:USERPROFILE\.echo-hub\hub.log)"
exit 1
