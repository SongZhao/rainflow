#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/../rainflow-testflight-ready.zip}"
CHECKSUM_PATH="${OUTPUT_PATH}.sha256"
STAGING_PARENT="$(mktemp -d)"
STAGING_ROOT="$STAGING_PARENT/rainflow-testflight-ready"
trap 'rm -rf "$STAGING_PARENT"' EXIT

"$ROOT_DIR/scripts/check.sh"

mkdir -p "$STAGING_ROOT"
(
  cd "$ROOT_DIR"
  tar \
    --exclude='.git' \
    --exclude='.build' \
    --exclude='.swiftpm' \
    --exclude='node_modules' \
    --exclude='.next' \
    --exclude='build' \
    --exclude='*.xcodeproj' \
    --exclude='*.xcworkspace' \
    --exclude='Local.xcconfig' \
    --exclude='*.xcarchive' \
    --exclude='*.ipa' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -cf - .
) | (cd "$STAGING_ROOT" && tar -xf -)

rm -f "$OUTPUT_PATH" "$CHECKSUM_PATH"
(
  cd "$STAGING_PARENT"
  zip -qr "$OUTPUT_PATH" rainflow-testflight-ready
)
unzip -tq "$OUTPUT_PATH" >/dev/null
if unzip -Z1 "$OUTPUT_PATH" | grep -qE '(^|/)Local\.xcconfig$'; then
  echo "Packaging error: Local.xcconfig was included in the release archive." >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUTPUT_PATH" > "$CHECKSUM_PATH"
else
  shasum -a 256 "$OUTPUT_PATH" > "$CHECKSUM_PATH"
fi

echo "Created: $OUTPUT_PATH"
echo "Checksum: $CHECKSUM_PATH"
