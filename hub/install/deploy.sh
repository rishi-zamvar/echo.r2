#!/bin/sh
# Pull, reinstall deps, restart the agent, confirm the new sha is live.
set -eu
HUB=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(git -C "$HUB" rev-parse --show-toplevel 2>/dev/null) || { echo "not a git checkout" >&2; exit 1; }
cd "$ROOT"
git pull --ff-only
NEW=$(git rev-parse --short=7 HEAD)
(cd "$HUB" && npm ci --omit=dev)
launchctl kickstart -k "gui/$(id -u)/com.rishizamvar.echo-hub"
i=0
while [ $i -lt 30 ]; do
  if curl -fs http://127.0.0.1:8790/health 2>/dev/null | grep -q "\"gitSha\":\"$NEW\""; then echo "deployed $NEW"; exit 0; fi
  i=$((i+1)); sleep 1
done
echo "deploy FAILED" >&2
exit 1
