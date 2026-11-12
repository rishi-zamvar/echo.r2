#!/bin/sh
# Record phone<->Even Terminal link drops with context, for cross-referencing.
# Usage: sh netwatch.sh [phone_ip] [port]   → appends to ~/.echo-hub/netwatch.log
# DROP events also dump a detail block to ~/.echo-hub/netwatch-drops/<ts>.txt
# ponytail: polling every 2 s; switch to an event source if 2 s granularity isn't enough.
PHONE=${1:-100.120.95.17}; PORT=${2:-3456}
LOG="$HOME/.echo-hub/netwatch.log"; DROPS="$HOME/.echo-hub/netwatch-drops"; TS=/usr/local/bin/tailscale
ETLOG="$HOME/.even-terminal/logs/even-terminal.log"
mkdir -p "$DROPS"
prev=-1; tick=0; prevpath=""; previf=""
phonepath() { $TS status 2>/dev/null | awk -v ip="$PHONE" '$1==ip {$1=$2=$3=$4="";print}' | sed 's/^ *//'; }
kind() { case "$1" in *direct*) echo direct;; *relay*) echo relay;; *idle*) echo idle;; *) echo "${1:-none}";; esac; }
etproc() { p=$(ps -axo pid=,command= | awk '/node .*bin\/even-terminal/ && !/awk/ {print $1; exit}'); [ -n "$p" ] && echo "pid=$p rss_kb=$(ps -o rss= -p $p | tr -d ' ') up=$(ps -o etime= -p $p | tr -d ' ')" || echo "NOT RUNNING"; }
snap() {
  hub=$(curl -s -m 1 127.0.0.1:8790/health >/dev/null && echo up || echo down)
  echo "path=[$(phonepath)] if=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}') hub=$hub load=[$(sysctl -n vm.loadavg | tr -d '{}')] et=[$(etproc)]"
}
detail() {  # $1 = timestamp
  f="$DROPS/$1.txt"
  { echo "== DROP $1"; echo "== snapshot"; snap
    echo "== tailscale ping"; $TS ping -c 2 --timeout 2s "$PHONE" 2>&1 | tail -2
    echo "== tailscale status (phone)"; phonepath
    echo "== wifi"; system_profiler SPAirPortDataType 2>/dev/null | grep -E "Signal / Noise|Transmit Rate|Channel|PHY Mode" | head -4
    echo "== default route"; route -n get default 2>/dev/null | grep -E "interface|gateway"
    echo "== power (last sleep/wake)"; pmset -g log 2>/dev/null | grep -E " (Sleep|Wake|DarkWake) " | tail -3 | cut -c1-160
    echo "== even-terminal log (last 25 lines, 200 chars)"; [ -f "$ETLOG" ] && tail -25 "$ETLOG" | cut -c1-200
    echo "== tcp to phone now"; lsof -nP -iTCP:$PORT 2>/dev/null | grep "$PHONE"
  } > "$f" 2>&1
  echo "$f"
}
echo "$(date -u +%FT%TZ) START phone=$PHONE port=$PORT $(snap)" >> "$LOG"
while :; do
  n=$(lsof -nP -iTCP:$PORT -sTCP:ESTABLISHED 2>/dev/null | grep -c "$PHONE")
  now=$(date -u +%FT%TZ)
  p=$(kind "$(phonepath)"); i=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  [ -n "$prevpath" ] && [ "$p" != "$prevpath" ] && echo "$now PATHCHANGE $prevpath->$p" >> "$LOG"
  [ -n "$previf" ] && [ "$i" != "$previf" ] && echo "$now IFCHANGE $previf->$i" >> "$LOG"
  if [ "$prev" -gt 0 ] && [ "$n" -eq 0 ]; then
    echo "$now DROP conns=$prev->0 $(snap) detail=$(detail "$now")" >> "$LOG"
  elif [ "$prev" -eq 0 ] && [ "$n" -gt 0 ]; then
    echo "$now RECONNECT conns=0->$n $(snap)" >> "$LOG"
  fi
  tick=$((tick+1)); [ $((tick % 30)) -eq 0 ] && echo "$now beat conns=$n $(snap)" >> "$LOG"
  prev=$n; prevpath=$p; previf=$i; sleep 2
done
