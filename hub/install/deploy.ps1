# UNVERIFIED on Windows until plan 02-07 (PC down).
# Pull, reinstall deps, restart the task, confirm the new sha is live.
$ErrorActionPreference = 'Stop'

$hub = Split-Path -Parent $PSScriptRoot
$root = $null
try { $root = git -C $hub rev-parse --show-toplevel } catch { }
if ($LASTEXITCODE -or -not $root) { Write-Error 'not a git checkout'; exit 1 }

git -C $root pull --ff-only
if ($LASTEXITCODE) { Write-Error 'git pull failed'; exit 1 }
$new = (git -C $root rev-parse --short=7 HEAD).Trim()

Push-Location $hub
npm ci --omit=dev
if ($LASTEXITCODE) { Pop-Location; exit 1 }
Pop-Location

Stop-ScheduledTask -TaskName echo-hub -ErrorAction SilentlyContinue
# Free the port if a hub node process outlived the task.
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine.Contains('server.js') -and $_.CommandLine.Contains($hub) } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-ScheduledTask -TaskName echo-hub

for ($i = 0; $i -lt 30; $i++) {
  try {
    $h = Invoke-RestMethod -Uri 'http://127.0.0.1:8790/health' -TimeoutSec 2
    if ($h.gitSha -eq $new) { Write-Output "deployed $new"; exit 0 }
  } catch { }
  Start-Sleep -Seconds 1
}
Write-Error 'deploy FAILED'
exit 1
