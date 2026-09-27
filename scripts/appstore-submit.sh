#!/usr/bin/env bash
# Optional App Store Connect Submit for Review.
#
# Safe default: dry-run (read ASC + print plan).
# Real submit: requires --confirm AND sets PILOT_ALLOW_APPSTORE_SUBMIT=1 for the
# Python helper. Never part of `pilot run … --ship` (use --ship-appstore only).
#
#   appstore-submit.sh <product> --dry-run
#   appstore-submit.sh <product> --confirm
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: appstore-submit.sh <product> [--dry-run|--confirm]}"
MODE="${2:---dry-run}"

if [[ "$P_TYPE" != "app" ]]; then
  err "$P_NAME is not an app — App Store submit only applies to type=app"
  exit 1
fi
if [[ -z "${P_TF_KEY:-}" ]]; then
  err "$P_NAME has no tf_key in products.json (needed to map to ASC app)"
  exit 1
fi
if [[ ! -f "$TF_KIT/config.sh" ]]; then
  err "kits/testflight/config.sh missing — see docs/SETUP.md"
  exit 1
fi

SCRIPT="$ASC_KIT/submit-for-review.py"
if [[ ! -f "$SCRIPT" ]]; then
  err "missing $SCRIPT"
  exit 1
fi

case "$MODE" in
  --dry-run|"")
    log "App Store submit DRY-RUN for $P_NAME (tf_key=$P_TF_KEY) — no reviewSubmission"
    python3 "$SCRIPT" "$P_TF_KEY" --dry-run
    ok "Dry-run finished. Nothing was submitted."
    ;;
  --confirm)
    log "App Store Submit for Review for $P_NAME (EXPLICIT --confirm)"
    warn "This sends the editable ASC version to Apple Review."
    export PILOT_ALLOW_APPSTORE_SUBMIT=1
    python3 "$SCRIPT" "$P_TF_KEY" --execute
    ok "$P_NAME submitted for App Review (check ASC for Waiting for Review)"
    ;;
  *)
    err "usage: appstore-submit.sh <product> [--dry-run|--confirm]"
    exit 1
    ;;
esac
