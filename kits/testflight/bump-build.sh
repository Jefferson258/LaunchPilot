#!/usr/bin/env bash
# Increment CURRENT_PROJECT_VERSION (the TestFlight build number) for an app.
# App Store Connect rejects a re-used build number, so bump before every
# upload after the first.
#
#   ./bump-build.sh juicd            # auto-increments by 1
#   ./bump-build.sh velour 7         # set explicit build number 7
#
# The marketing version (1.0) is left alone; change that in Xcode when you
# ship a new public version.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_app "${1:?Usage: ./bump-build.sh <juicd|velour> [build-number]}"

current="$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ" | grep -oE '[0-9]+' || echo 0)"
if [[ -n "${2:-}" ]]; then
  new="$2"
else
  new=$((current + 1))
fi

perl -pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${new};/g" "$PBXPROJ"
log "$APP_DISPLAY build number: $current -> $new"
