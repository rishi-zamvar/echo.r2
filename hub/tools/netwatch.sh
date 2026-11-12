#!/bin/sh
# Record phone<->Even Terminal link drops with context, for cross-referencing.
# Usage: sh netwatch.sh [phone_ip] [port]   → appends to ~/.echo-hub/netwatch.log
# ponytail: polling every 2 s; switch to an event source if 2 s granularity isn't enough.
PHONE=${1:-100.120.95.17}; PORT=${2:-3456}
LOG="$HOME/.echo-hub/netwatch.log"; TS=/usr/local/bin/tailscale
prev=-1; tick=0
snap() {
  path=$($TS status 2>/dev/null | awk -v ip="$PHONE" '$1==ip {$1=$2=$3=$4="";print}' | sed 's/^ *//')
  wifi=$(ipconfig getsummary en0 2>/dev/null | awk -F' : ' '/ SSID/{print $2; exit}')
  hub=$(curl -s -m 1 127.0.0.1:8790/health >/dev/null && echo up || echo down)
  load=$(sysctl -n vm.loadavg | tr -d '{}')
  echo "path=[$path] wifi=[$wifi] hub=$hub load=[$load]"
}
echo "$(date -u +%FT%TZ) START phone=$PHONE port=$PORT $(snap)" >> "$LOG"
while :; do
  n=$(lsof -nP -iTCP:$PORT -sTCP:ESTABLISHED 2>/dev/null | grep -c "$PHONE")
  now=$(date -u +%FT%TZ)
  if [ "$prev" -gt 0 ] && [ "$n" -eq 0 ]; then
    echo "$now DROP conns=$prev->0 $(snap) ping=[$($TS ping -c 1 --timeout 2s $PHONE 2>&1 | tail -1)]" >> "$LOG"
  elif [ "$prev" -eq 0 ] && [ "$n" -gt 0 ]; then
    echo "$now RECONNECT conns=0->$n $(snap)" >> "$LOG"
  fi
  tick=$((tick+1)); [ $((tick % 30)) -eq 0 ] && echo "$now beat conns=$n $(snap)" >> "$LOG"
  prev=$n; sleep 2
done
