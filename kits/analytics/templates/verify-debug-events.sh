#!/bin/bash
# Template: copy to <product-repo>/scripts/verify-analytics-debug.sh and fill
# in APP_PATH / BUNDLE_ID / LAUNCH_ARGS below (or export them as env vars).
#
# Proves the debug sink -> JSONL file path end-to-end without any network and
# without XCUITest UI automation (which can be flaky/slow in some CI or
# sandboxed shells — see LaunchPilot docs/ANALYTICS.md "Testing notes").
# Installs the already-built .app onto a booted (or specified) simulator,
# launches it with the given launch arguments, waits a few seconds for the
# app_open event to fire, then reads and prints
# Documents/analytics-debug-events.jsonl straight out of the simulator's app
# container on the host filesystem.
#
# Usage:
#   APP_PATH=/path/to/Product.app BUNDLE_ID=com.example.product \
#     ./verify-analytics-debug.sh [device-udid-or-name]
#
# Exit code 0 + prints recorded events on success; exit 1 if no debug file or
# no app_open event was found.

set -euo pipefail

APP_PATH="${APP_PATH:?Set APP_PATH to the built .app (e.g. find DerivedData .../Debug-iphonesimulator/*.app)}"
BUNDLE_ID="${BUNDLE_ID:?Set BUNDLE_ID to the app's bundle identifier}"
LAUNCH_ARGS=(${LAUNCH_ARGS:-"-skipTutorial" "-acceptLegalTerms" "-seedDemoData"})
DEVICE="${1:-booted}"

echo "==> Installing $APP_PATH on device '$DEVICE'"
xcrun simctl install "$DEVICE" "$APP_PATH"

echo "==> Launching $BUNDLE_ID ${LAUNCH_ARGS[*]}"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"

echo "==> Waiting for app_open to be written..."
sleep 4

CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
JSONL="$CONTAINER/Documents/analytics-debug-events.jsonl"

if [[ ! -f "$JSONL" ]]; then
  echo "FAIL: no debug JSONL file found at $JSONL" >&2
  echo "(check that JUICD_ANALYTICS_PROVIDER / equivalent isn't set to 'none' and analytics_enabled != 0)" >&2
  exit 1
fi

echo "==> Events recorded so far (all launches, oldest first):"
cat "$JSONL"

if ! grep -q '"name":"app_open"' "$JSONL"; then
  echo "FAIL: no app_open event found in $JSONL" >&2
  exit 1
fi

echo
echo "PASS: debug sink wrote events to $JSONL with no network access."
