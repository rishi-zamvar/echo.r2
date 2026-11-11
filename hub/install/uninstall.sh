#!/bin/sh
set -eu
LABEL=com.rishizamvar.echo-hub
HUB=$(cd "$(dirname "$0")/.." && pwd)
DATA=${ECHO_DATA_DIR:-$HOME/.echo-hub}
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
node "$HUB/install/hooks-merge.js" unmerge
echo "uninstalled (data kept in $DATA)"
