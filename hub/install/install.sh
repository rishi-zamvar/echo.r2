#!/bin/sh
# Install the echo hub as a per-user launchd agent and optionally merge Claude hooks (--global-hooks; off by default, Even Terminal shares settings.json). --dry-run prints the plist only.
set -eu
LABEL=com.rishizamvar.echo-hub
DRY=0; GH=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --global-hooks) GH=1;; esac; done
HUB=$(cd "$(dirname "$0")/.." && pwd)
NODE=$(command -v node || true); [ -n "$NODE" ] || { echo "node not found" >&2; exit 1; }
CLAUDE_BIN=$(command -v claude || true); [ -n "$CLAUDE_BIN" ] || { echo "claude not found" >&2; exit 1; }
DATA=${ECHO_DATA_DIR:-$HOME/.echo-hub}
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
PATHV=$(dirname "$NODE"):$(dirname "$CLAUDE_BIN"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

PLIST_TEXT=$(cat <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$NODE</string><string>$HUB/server.js</string></array>
  <key>WorkingDirectory</key><string>$HUB</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$PATHV</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$DATA/launchd.log</string>
  <key>StandardErrorPath</key><string>$DATA/launchd.log</string>
</dict>
</plist>
PL
)

if [ $DRY = 1 ]; then printf '%s\n' "$PLIST_TEXT"; [ $GH = 1 ] && echo "global hooks: on" || echo "global hooks: off"; exit 0; fi

mkdir -p "$DATA" "$HOME/Library/LaunchAgents"; chmod 700 "$DATA"
(cd "$HUB" && npm ci --omit=dev)
[ $GH = 1 ] && "$NODE" "$HUB/install/hooks-merge.js" merge
TMP=$(mktemp "${TMPDIR:-/tmp}/echo-hub.XXXXXX")
printf '%s\n' "$PLIST_TEXT" > "$TMP"
plutil -lint "$TMP" >/dev/null
mv "$TMP" "$PLIST"
UIDN=$(id -u)
launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$UIDN" "$PLIST" || { sleep 2; launchctl bootstrap "gui/$UIDN" "$PLIST"; }
i=0
while [ $i -lt 20 ]; do
  if H=$(curl -fs http://127.0.0.1:8790/health); then
    echo "installed $(printf '%s' "$H" | sed -n 's/.*"gitSha":"\([^"]*\)".*/\1/p')"
    echo "next: node hub/cli.js pair <name>; disable Tailscale key expiry for this machine"
    exit 0
  fi
  i=$((i+1)); sleep 1
done
echo "install FAILED (see $DATA/hub.log and $DATA/launchd.log)" >&2
exit 1
