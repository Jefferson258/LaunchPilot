#!/usr/bin/env bash
# Optional App Store Connect Submit for Review.
#
# Safe default: dry-run (read ASC + print plan).
# Real submit: requires --confirm AND sets PILOT_ALLOW_APPSTORE_SUBMIT=1 for the
# Python helper. Never part of `pilot run … --ship` (use --ship-appstore only).
#
# Phased vs regular (version updates only; default = regular / not phased):
#   --phased      Apple Phased Release for Automatic Updates (7-day ramp)
#   --no-phased   Regular/immediate release (explicit; same as omitting both)
#
#   appstore-submit.sh <product> [--dry-run|--confirm] [--phased|--no-phased]
#   appstore-submit.sh <product> --dry-run --phased
#   appstore-submit.sh <product> --confirm --phased
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: appstore-submit.sh <product> [--dry-run|--confirm] [--phased|--no-phased]}"
shift

MODE="--dry-run"
PHASED_FLAG=""  # empty | --phased | --no-phased (bash 3.2 + set -u safe)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="--dry-run"
      shift
      ;;
    --confirm)
      MODE="--confirm"
      shift
      ;;
    --phased)
      if [[ -n "$PHASED_FLAG" ]]; then
        err "--phased and --no-phased are mutually exclusive"
        exit 1
      fi
      PHASED_FLAG="--phased"
      shift
      ;;
    --no-phased)
      if [[ -n "$PHASED_FLAG" ]]; then
        err "--phased and --no-phased are mutually exclusive"
        exit 1
      fi
      PHASED_FLAG="--no-phased"
      shift
      ;;
    *)
      err "usage: appstore-submit.sh <product> [--dry-run|--confirm] [--phased|--no-phased]"
      exit 1
      ;;
  esac
done

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

py_args=("$P_TF_KEY")
case "$MODE" in
  --dry-run) py_args+=(--dry-run) ;;
  --confirm) py_args+=(--execute) ;;
  *)
    err "usage: appstore-submit.sh <product> [--dry-run|--confirm] [--phased|--no-phased]"
    exit 1
    ;;
esac
if [[ -n "$PHASED_FLAG" ]]; then
  py_args+=("$PHASED_FLAG")
fi

case "$MODE" in
  --dry-run)
    if [[ -n "$PHASED_FLAG" ]]; then
      log "App Store submit DRY-RUN for $P_NAME (tf_key=$P_TF_KEY; $PHASED_FLAG) — no reviewSubmission"
    else
      log "App Store submit DRY-RUN for $P_NAME (tf_key=$P_TF_KEY; regular release) — no reviewSubmission"
    fi
    python3 "$SCRIPT" "${py_args[@]}"
    ok "Dry-run finished. Nothing was submitted."
    ;;
  --confirm)
    if [[ -n "$PHASED_FLAG" ]]; then
      log "App Store Submit for Review for $P_NAME (EXPLICIT --confirm; $PHASED_FLAG)"
    else
      log "App Store Submit for Review for $P_NAME (EXPLICIT --confirm; regular release)"
    fi
    warn "This sends the editable ASC version to Apple Review."
    export PILOT_ALLOW_APPSTORE_SUBMIT=1
    python3 "$SCRIPT" "${py_args[@]}"
    ok "$P_NAME submitted for App Review (check ASC for Waiting for Review)"
    ;;
esac
