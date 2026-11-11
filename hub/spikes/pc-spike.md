# echo.r2 Phase 1 - PC spikes S1-S7 (PowerShell runbook)

Purpose: verify Windows/ConPTY assumptions A1-A6 on the real PC. Read-only diagnostics.

Rules (strict):
- Everything stays on 127.0.0.1. Add NO firewall rule. Stop the hub if it is running (the probe uses port 8791).
- Do NOT edit `~/.claude/settings.json`. Never use `--dangerously-skip-permissions`.
- Use a throwaway, already-trusted directory as `<trusted-cwd>` (run `claude` there once by hand and accept the trust dialog, then exit), e.g. `$env:USERPROFILE\spike-cwd`.
- When done: kill every spike `claude`/`node` process (see end) and report.

## Preconditions

```powershell
node -v    # need v24 (or >=22). If missing: winget install OpenJS.NodeJS.LTS
git clone https://github.com/rishi-zamvar/echo.r2 $env:USERPROFILE\Projects\echo.r2   # or: git pull
cd $env:USERPROFILE\Projects\echo.r2\hub
npm ci
mkdir $env:USERPROFILE\spike-cwd -Force
```

## S1 - prebuild + claude resolution

```powershell
node -v; node -p "process.platform+'-'+process.arch"
Test-Path node_modules\node-pty\prebuilds\win32-x64\conpty.node; Test-Path node_modules\node-pty\build   # expect True / False (no compile)
where.exe claude; claude --version; Get-Command claude | Format-List Source
Test-Path $env:USERPROFILE\.local\bin\claude.exe
$c = (where.exe claude | Select-Object -First 1)
node -e "const p=require('node-pty').spawn(process.argv[1],['--version'],{name:'xterm-256color',cols:120,rows:30,cwd:process.cwd(),env:process.env});p.onData(d=>process.stdout.write(d));p.onExit(e=>console.log('exit',e))" $c
```

Report: node version, whether a native compile ran, absolute claude path, `.cmd` vs `.exe`, `--version` through the PTY.
Expected: prebuild present, no `build` dir, `claude.exe` resolves, version prints.
Repeat once from a Task Scheduler-launched shell (see "Scheduled-task repeat" below) for the PATH question.

## S2 - TUI under ConPTY

```powershell
cd $env:USERPROFILE\Projects\echo.r2\hub
node spikes/spike-tui.mjs $env:USERPROFILE\spike-cwd
```

The probe prints labeled steps `== S2.1` .. `== S2.7`, then `== S5 hooks seen so far`, then `PTY_PID <n>` and waits for Enter (that is S4, leave it waiting while you do S4 below).
Report per step (paste the labeled output):
- S2.1 TUI drew? trust/first-run dialogs?
- S2.2 Claude answered "pong"? `stop_hook_fired` true?
- S2.3 paste with newline accepted as one message?
- S2.4 arrows harmless; UTF-8 `naïve café 日本語` echoed intact?
- S2.5 bytes after resize 100x40 -> 120x30 (repaint?)
- S2.6 `interrupted_seen`, `output_stopped`
- S2.7 bytes within 500 ms after rows+1/rows nudge (full-screen repaint?)
Expected: all work like on the Mac; S2.5/S2.7 several KB of repaint.

## S3 - bash-tool child + orphan check (uses S2 session)

While the probe is waiting at `PTY_PID`, from a second PowerShell:

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'claude|node|conhost|OpenConsole' } | Select ProcessId,ParentProcessId,Name | Format-Table
```

Report: is `PTY_PID` the claude pid or conhost/agent? Full descendant list.
Variant: before pressing Enter, in a SEPARATE manual run (`node spikes/spike-tui.mjs ...` again, wait for S2.7 to finish), cannot type into the probe, so instead run `claude` by hand in `spike-cwd`, ask it to run `ping -n 120 127.0.0.1`, then take the process list above and use it in S4 below.

## S4 - tree kill and orphans

```powershell
# <P> = PTY_PID printed by the probe
taskkill /PID <P> /T /F
Start-Sleep 2
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'claude' } | Select ProcessId,Name
```

Then press Enter in the probe (it reports `onExit`).
Report: `claude.exe` left after? Also run the probe once more and press Enter WITHOUT taskkill after `pty.kill()` only (probe calls `p.kill()` at the end) and list leftovers. Grandchild test: with the `ping -n 120 127.0.0.1` session above, after `taskkill /PID <P> /T /F` does `ping.exe` survive (`Get-Process ping`)?
Repeat S4 once from a Task Scheduler-launched shell.

## S5 - hooks

The probe already runs http hooks (`--settings`, header `X-Echo-Secret`, `allowedEnvVars`). Report from its output:
- Stop `HOOK` line verbatim (redact paths if needed) and `secret=true` (header interpolated).
- Notification: in a separate probe run, cannot type, so use a manual claude with the same settings: write the hooks JSON from the probe (temp `echo-spike-*.json` in `$env:TEMP` is deleted at exit; copy it first while the probe is waiting at `PTY_PID`) and run `claude --settings <copy>` in a cwd with no allow rules, asking: "run `echo hi > x.txt`". Start a listener first: `node -e "require('http').createServer((q,r)=>{let b='';q.on('data',d=>b+=d);q.on('end',()=>{console.log(q.method,q.url,q.headers['x-echo-secret'],b);r.writeHead(200);r.end()})}).listen(8791,'127.0.0.1')"` (set `ECHO_SECRET=x` in that shell and the copy's header will match). Report Notification body (`notification_type`, `message`).
- SubagentStop: ask "use the Explore agent to list files"; report the body.
- Only if http hooks do NOT fire: repeat with a command hook `{"type":"command","command":"node","args":["C:\\path\\hook.js"],"timeout":2}` (D-14) and report.

## S6 - transcripts

```powershell
Get-ChildItem $env:USERPROFILE\.claude\projects -Directory | Select Name -First 5
Get-ChildItem $env:USERPROFILE\.claude\projects\*\<uuid>.jsonl      # <uuid> printed on the probe's CMD line
Get-ChildItem $env:USERPROFILE\.claude\sessions | Select -First 3; Get-Content (Get-ChildItem $env:USERPROFILE\.claude\sessions\*.json | Select -First 1)
```

Report: encoded dir name for e.g. `C:\Users\X\proj`; whether `<uuid>.jsonl` existed before the first prompt (probe prints `transcript_before_prompt` / `transcript_after_prompt`); `entrypoint` of the hub session (`cli`?) and of an Even Terminal session if one exists; whether `~/.claude/sessions/<pid>.json` exists.

## S7 - fixture

Copy 12-15 lines of a real PC transcript, sanitize paths/content, and send as `fixtures/transcript-pc.jsonl`. Read it while a session is mid-answer and note partial-line handling and any line over 100 KB.

## Scheduled-task repeat (S1 and S4)

```powershell
schtasks /create /tn echoSpike /sc once /st 23:59 /tr "powershell -File C:\path\spike.ps1"
schtasks /run /tn echoSpike
schtasks /delete /tn echoSpike /f
```
`spike.ps1` should run the S1 commands and write output to a file; report whether `claude.exe` resolves from that shell.

## Cleanup (mandatory)

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'claude' } | ForEach-Object { taskkill /PID $_.ProcessId /T /F }
Get-Process ping -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'claude|ping' } | Select ProcessId,Name   # expect empty
```

## Results template (reply with this filled in)

```
## S1
Result:
Raw evidence:
Verdict: PASS|FAIL|DIVERGES
Impact on hub:
(repeat for S2 .. S7)
```
