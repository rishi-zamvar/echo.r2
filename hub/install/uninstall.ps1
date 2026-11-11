# UNVERIFIED on Windows until plan 02-07 (PC down). Run from an elevated PowerShell.
# Removes the echo-hub task, firewall rule, and Claude hook entries. Data dir is kept.
$ErrorActionPreference = 'Stop'

$hub = Split-Path -Parent $PSScriptRoot
$node = (Get-Command node.exe -ErrorAction Stop).Source

Stop-ScheduledTask -TaskName echo-hub -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName echo-hub -Confirm:$false -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName echo-hub -ErrorAction SilentlyContinue | Remove-NetFirewallRule

& $node "$hub\install\hooks-merge.js" unmerge
if ($LASTEXITCODE) { exit 1 }

Write-Output "uninstalled (data kept in $env:USERPROFILE\.echo-hub)"
