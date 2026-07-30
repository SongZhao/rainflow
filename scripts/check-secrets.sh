#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if find "$ROOT_DIR" -type f \
  -not -path '*/.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.next/*' \
  -not -path '*/.build/*' \
  -not -name '*.png' \
  -not -name '*.zip' \
  -not -path "$ROOT_DIR/scripts/check-secrets.sh" \
  -print0 | xargs -0 grep -nE '(service_role|SUPABASE_SERVICE_ROLE_KEY|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' >/tmp/rainflow-secret-scan.txt; then
  echo "Potential server secret/private key detected:" >&2
  cat /tmp/rainflow-secret-scan.txt >&2
  exit 1
fi

if [[ -f "$ROOT_DIR/apps/ios/Config/Local.xcconfig" ]]; then
  echo "Local.xcconfig exists locally and must remain uncommitted."
fi
