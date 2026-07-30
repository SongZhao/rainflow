#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
CONFIG_FILE="$IOS_DIR/Config/Local.xcconfig"
CONFIG_EXAMPLE="$IOS_DIR/Config/Local.xcconfig.example"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode is required. Install it, open it once, and rerun." >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Finish Xcode first-launch setup and accept the license, then rerun." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "Install Homebrew and run: brew install xcodegen" >&2
    exit 1
  fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
  echo "Created $CONFIG_FILE"
  echo "Fill in the Supabase URL, publishable key, Apple Team ID, and bundle identifier before a device or archive build."
fi

"$ROOT_DIR/scripts/check.sh"

pushd "$IOS_DIR" >/dev/null
xcodegen generate
xcodebuild -resolvePackageDependencies \
  -project Rainflow.xcodeproj \
  -scheme Rainflow

xcodebuild \
  -project Rainflow.xcodeproj \
  -scheme Rainflow \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
popd >/dev/null

echo
echo "Bootstrap complete. Open apps/ios/Rainflow.xcodeproj in Xcode."
