#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v supabase >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    brew install supabase/tap/supabase
  else
    echo "Install the Supabase CLI, then rerun this script." >&2
    exit 1
  fi
fi

cat <<'MESSAGE'
Use a disposable development Supabase project for this first run. The CLI opens
an authenticated browser flow; do not paste service-role keys into this repository.
MESSAGE

supabase login
read -r -p "Supabase project reference: " PROJECT_REF
if [[ ! "$PROJECT_REF" =~ ^[a-z0-9]{20}$ ]]; then
  echo "The project reference should be the 20-character lowercase project ID." >&2
  exit 1
fi

cd "$ROOT_DIR"
supabase link --project-ref "$PROJECT_REF"
supabase db push

echo
cat <<'MESSAGE'
Migrations were submitted. Now configure the Auth email template to include the
numeric email token:

  Supabase Dashboard -> Authentication -> Emails -> Magic Link

Use supabase/auth-email-templates.md as the copy-paste template. The default
link-only email does not work with Rainflow's iPhone code-entry screen.

Then verify the RLS/receipt checks in docs/TESTFLIGHT.md with two separate test
users.
MESSAGE
