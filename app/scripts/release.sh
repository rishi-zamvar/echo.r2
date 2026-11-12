#!/usr/bin/env bash
# Usage: sh app/scripts/release.sh [--dry-run]
# project.yml -> archive -> TestFlight upload (needs Xcode signed in + iOS platform + 6 GB free).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=$(date +%Y%m%d.%H%M)
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

ARCHIVE=(xcodebuild archive -project EchoR2.xcodeproj -scheme EchoR2 -configuration Release
  -destination 'generic/platform=iOS' -archivePath build/release/EchoR2.xcarchive
  -derivedDataPath build/release/dd -allowProvisioningUpdates "CURRENT_PROJECT_VERSION=$BUILD")
EXPORT=(xcodebuild -exportArchive -archivePath build/release/EchoR2.xcarchive
  -exportPath build/release/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates)

FAIL=0
bad() { echo "preflight: $1"; FAIL=1; }

command -v xcodegen >/dev/null || bad "xcodegen not installed (brew install xcodegen)"
FREE=$(( $(df -k . | awk 'NR==2{print $4}') / 1048576 ))
[ "$FREE" -ge 6 ] || bad "need 6 GB free, have $FREE GB"
if command -v xcodegen >/dev/null; then
  xcodegen generate >/dev/null
  xcodebuild -project EchoR2.xcodeproj -scheme EchoR2 -showdestinations 2>&1 | grep -q "is not installed" \
    && bad "iOS platform not installed: Xcode > Settings > Components, or xcodebuild -downloadPlatform iOS"
fi

if [ "$DRY" = 1 ]; then
  echo "+ ${ARCHIVE[*]}"
  echo "+ ${EXPORT[*]}"
  echo "dry run: version $VERSION build $BUILD, preflight $([ $FAIL = 0 ] && echo ok || echo FAILED)"
  exit 0
fi
[ "$FAIL" = 0 ] || exit 1

rm -rf build/release
if "${ARCHIVE[@]}" && "${EXPORT[@]}"; then
  rm -rf build/release
  echo "uploaded EchoR2 $VERSION ($BUILD) to App Store Connect; it appears in TestFlight after processing"
else
  echo "failed; left $PWD/build/release for diagnosis. rm -rf app/build/release to free space" >&2
  exit 1
fi
