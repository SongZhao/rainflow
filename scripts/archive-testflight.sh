#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
CONFIG_FILE="$IOS_DIR/Config/Local.xcconfig"
ARCHIVE_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$ARCHIVE_DIR/Rainflow.xcarchive"

read_xcconfig_value() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\\1/p" "$CONFIG_FILE" \
    | tail -n 1 \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

require_value() {
  local key="$1"
  local value
  value="$(read_xcconfig_value "$key")"
  if [[ -z "$value" ]]; then
    echo "$key is empty in $CONFIG_FILE." >&2
    exit 1
  fi
  if [[ "$value" =~ YOUR_PROJECT_REF|REPLACE_ME|REPLACE_WITH|com\.yourcompany ]]; then
    echo "$key still contains a placeholder in $CONFIG_FILE." >&2
    exit 1
  fi
  printf '%s' "$value"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Archiving requires macOS and Xcode." >&2
  exit 1
fi

for command_name in xcodebuild xcodegen; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Run scripts/bootstrap-mac.sh and fill in the values." >&2
  exit 1
fi

SUPABASE_URL="$(require_value SUPABASE_URL)"
SUPABASE_KEY="$(require_value SUPABASE_PUBLISHABLE_KEY)"
TEAM_ID="$(require_value DEVELOPMENT_TEAM)"
BUNDLE_ID="$(require_value PRODUCT_BUNDLE_IDENTIFIER)"

if [[ "$SUPABASE_URL" != https:*supabase.co* ]]; then
  echo "SUPABASE_URL must be the hosted HTTPS Supabase project URL." >&2
  exit 1
fi
if [[ "$SUPABASE_KEY" != sb_publishable_* && ${#SUPABASE_KEY} -le 40 ]]; then
  echo "SUPABASE_PUBLISHABLE_KEY does not look like a public client key." >&2
  exit 1
fi
if [[ ! "$TEAM_ID" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "DEVELOPMENT_TEAM must be the 10-character Apple Team ID." >&2
  exit 1
fi
if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]]; then
  echo "PRODUCT_BUNDLE_IDENTIFIER is not valid." >&2
  exit 1
fi

"$ROOT_DIR/scripts/check.sh"

mkdir -p "$ARCHIVE_DIR"
pushd "$IOS_DIR" >/dev/null
xcodegen generate
xcodebuild -resolvePackageDependencies \
  -project Rainflow.xcodeproj \
  -scheme Rainflow
xcodebuild \
  -project Rainflow.xcodeproj \
  -scheme Rainflow \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  clean archive
popd >/dev/null

echo "Archive created at: $ARCHIVE_PATH"
echo "Open it with: open '$ARCHIVE_PATH'"
echo "Then use Xcode Organizer to Validate and Distribute to App Store Connect/TestFlight."
