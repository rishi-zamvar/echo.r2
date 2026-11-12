#!/bin/bash
# Usage: sh app/scripts/test.sh unit|snapshot|ui|all   (SNAPSHOT_RECORD=1 re-records snapshots)
set -euo pipefail
cd "$(dirname "$0")/.."

SIM=echo-iPhone17
DEST="platform=iOS Simulator,name=$SIM"
MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true' EXIT

xcodegen generate >/dev/null
xcrun simctl list devices | grep -q "$SIM" || \
  xcrun simctl create "$SIM" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-26-0 >/dev/null

sim_test() { # $1 = only-testing target
  xcodebuild test -project EchoR2.xcodeproj -scheme EchoR2 -destination "$DEST" \
    -only-testing:"$1" -skipPackagePluginValidation -skipMacroValidation \
    -derivedDataPath "$PWD/build/test-dd" CODE_SIGNING_ALLOWED=NO
}

run() {
  case "$1" in
    unit) xcodebuild test -project EchoR2.xcodeproj -scheme EchoR2Tests -destination platform=macOS ;;
    snapshot)
      export TEST_RUNNER_SNAPSHOT_RECORD="${SNAPSHOT_RECORD:-0}"
      sim_test EchoR2AppTests ;;
    ui)
      node ../hub/tools/mock-hub.mjs 8799 >/dev/null 2>&1 &
      MOCK_PID=$!
      for _ in $(seq 20); do curl -fs 127.0.0.1:8799/health >/dev/null && break; sleep 0.5; done
      curl -fs 127.0.0.1:8799/health >/dev/null
      sim_test EchoR2UITests ;;
  esac
}

case "${1:-all}" in
  unit|snapshot|ui) suites=("$1") ;;
  all) suites=(unit snapshot ui) ;;
  *) echo "usage: test.sh unit|snapshot|ui|all" >&2; exit 2 ;;
esac
for s in "${suites[@]}"; do
  run "$s" || { echo "test.sh: $s FAILED"; exit 1; }
done
