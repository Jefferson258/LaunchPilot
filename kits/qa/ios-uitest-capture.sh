#!/usr/bin/env bash
# Shared iOS UITest screenshot capture for LaunchPilot products.
#
# Usage:
#   ios-uitest-capture.sh \
#     --project PATH.xcodeproj \
#     --scheme SchemeName \
#     --out DIR \
#     --derived DIR \
#     --sim-prefer "iPhone 17 Pro,iPhone 17,iPhone 16 Pro" \
#     --test "Target/Class/testA" \
#     [--test "Target/Class/testB"] \
#     [--clean-glob "01-*.png"] ...
#
set -euo pipefail

PROJECT=""
SCHEME=""
OUT=""
DERIVED=""
SIM_PREFER="iPhone 17 Pro,iPhone 17,iPhone 16e,iPhone 16 Pro"
SIM_NAME_OVERRIDE="${QA_SIM_NAME:-}"
TESTS=()
CLEAN_GLOBS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --scheme) SCHEME="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --derived) DERIVED="${2:?}"; shift 2 ;;
    --sim-prefer) SIM_PREFER="${2:?}"; shift 2 ;;
    --test) TESTS+=("${2:?}"); shift 2 ;;
    --clean-glob) CLEAN_GLOBS+=("${2:?}"); shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

: "${PROJECT:?--project required}"
: "${SCHEME:?--scheme required}"
: "${OUT:?--out required}"
: "${DERIVED:?--derived required}"
if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "at least one --test required" >&2
  exit 1
fi

pick_sim() {
  if [[ -n "$SIM_NAME_OVERRIDE" ]]; then
    printf '%s' "$SIM_NAME_OVERRIDE"
    return
  fi
  local IFS=','
  local cand
  for cand in $SIM_PREFER; do
    cand="$(echo "$cand" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if xcrun simctl list devices available | grep -q "$cand"; then
      printf '%s' "$cand"
      return
    fi
  done
  return 1
}

SIM_NAME="$(pick_sim)" || {
  echo "No suitable simulator from: $SIM_PREFER (override with QA_SIM_NAME)" >&2
  exit 1
}
UDID="$(xcrun simctl list devices available | grep "$SIM_NAME" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')"
echo "==> UITest QA on $SIM_NAME ($UDID)"
echo "    project=$PROJECT scheme=$SCHEME"
echo "    tests: ${TESTS[*]}"

mkdir -p "$OUT" "$DERIVED"
xcrun simctl boot "$UDID" 2>/dev/null || true
export QA_SCREENSHOT_DIR="$OUT"

if [[ ${#CLEAN_GLOBS[@]} -gt 0 ]]; then
  for g in "${CLEAN_GLOBS[@]}"; do
    # shellcheck disable=SC2086
    rm -f "$OUT"/$g 2>/dev/null || true
  done
fi

for t in "${TESTS[@]}"; do
  echo "==> xcodebuild test -only-testing:$t"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    -only-testing:"$t" \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1
done

count="$(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
echo "Done. $count PNG(s) in $OUT"
test "$count" -gt 0
