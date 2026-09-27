#!/usr/bin/env bash
# Compile-check an app (no signing, no Apple login).
# Prefers the iOS Simulator destination; if CoreSimulator/simdiskimaged is
# flaky, falls back to generic/platform=iOS (device SDK) which still catches
# compile errors before archive.
#
#   ./build-check.sh juicd
#   ./build-check.sh velour
#   ./build-check.sh corvim
#   ./build-check.sh all
#
# Exit code is non-zero if any build fails.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sim_ok() {
  # Cheap probe: list runtimes without crashing when simdiskimaged is wedged.
  xcrun simctl list runtimes >/dev/null 2>&1
}

run_xcodebuild() {
  local dest="$1"
  local derived="$2"
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$dest" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E "error:|warning: .*deprecated|BUILD SUCCEEDED|BUILD FAILED|No available simulator runtimes" || true
  return "${PIPESTATUS[0]}"
}

check_one() {
  resolve_app "$1"
  local dest="$SIM_DEST"
  local label="simulator"
  local derived="/tmp/${APP_KEY}-derived"

  if ! sim_ok; then
    warn "Simulator service unhealthy — using generic iOS device destination"
    dest="generic/platform=iOS"
    label="device SDK"
    derived="/tmp/${APP_KEY}-derived-device"
  fi

  log "Compile-checking $APP_DISPLAY ($SCHEME) for ${label}..."
  set +e
  run_xcodebuild "$dest" "$derived"
  local rc=$?
  # Simulator dest can still fail with empty runtimes even when simctl list works briefly.
  if [[ $rc -ne 0 && "$dest" == "$SIM_DEST" ]]; then
    warn "Simulator build failed (rc=$rc) — retrying with generic/platform=iOS"
    dest="generic/platform=iOS"
    label="device SDK"
    derived="/tmp/${APP_KEY}-derived-device"
    run_xcodebuild "$dest" "$derived"
    rc=$?
  fi
  set -e
  if [[ $rc -eq 0 ]]; then
    log "$APP_DISPLAY: BUILD SUCCEEDED ($label)"
  else
    log "$APP_DISPLAY: BUILD FAILED (exit $rc, $label)"
  fi
  return $rc
}

target="${1:-all}"
fail=0
if [[ "$target" == "all" || "$target" == "both" ]]; then
  check_one juicd || fail=1
  check_one velour || fail=1
  check_one corvim || fail=1
else
  check_one "$target" || fail=1
fi
exit $fail
