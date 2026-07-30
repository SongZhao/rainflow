#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Rainflow's iPhone project must be prepared on a Mac with Xcode."
  read -r -p "Press Return to close."
  exit 1
fi

cat <<'MESSAGE'
Rainflow Mac preparation

This creates the Xcode project and performs a simulator build. It does not upload
to TestFlight and it does not ask for Apple passwords or private keys.

Before the app can sign in, create a disposable Supabase project and apply the two
migrations in supabase/migrations. The project URL and publishable key go in the
local configuration file created below.
MESSAGE

echo
"$ROOT_DIR/scripts/bootstrap-mac.sh"

CONFIG_FILE="$ROOT_DIR/apps/ios/Config/Local.xcconfig"
if [[ -f "$CONFIG_FILE" ]]; then
  echo
  echo "Local configuration: $CONFIG_FILE"
  open -t "$CONFIG_FILE"
fi

open "$ROOT_DIR/apps/ios/Rainflow.xcodeproj"

echo
cat <<'MESSAGE'
Xcode is opening. Fill in Local.xcconfig, select your Apple development team,
and run Rainflow on an iPhone. Use docs/TESTFLIGHT.md for the smoke and archive
steps.
MESSAGE
read -r -p "Press Return to close."
