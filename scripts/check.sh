#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pushd "$ROOT_DIR/packages/RainflowDomain" >/dev/null
swift test
popd >/dev/null

while IFS= read -r -d '' file; do
  swiftc -frontend -parse "$file" >/dev/null
done < <(find "$ROOT_DIR/apps/ios/Rainflow" "$ROOT_DIR/packages/RainflowDomain" -name '*.swift' -print0)

python3 "$ROOT_DIR/scripts/validate_project.py"
"$ROOT_DIR/scripts/check-secrets.sh"

echo "Static checks passed. Run scripts/bootstrap-mac.sh on macOS for the real iOS build."
