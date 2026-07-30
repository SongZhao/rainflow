#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
LOG_PATH="$ROOT_DIR/build/rainflow-ios-build.log"
mkdir -p "$ROOT_DIR/build"

cd "$IOS_DIR"
xcodegen generate
set +e
xcodebuild \
  -project Rainflow.xcodeproj \
  -scheme Rainflow \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$LOG_PATH"
status=${PIPESTATUS[0]}
set -e

echo
echo "Build log: $LOG_PATH"
if [[ $status -ne 0 ]]; then
  echo
  echo "Compiler errors:"
  grep -n -B 3 -A 8 'error:' "$LOG_PATH" || true
fi
exit "$status"
