#!/usr/bin/env bash
# Smoke test LaunchPilot without product secrets or Xcode.
#   pilot demo
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

PRODUCT="demo-site"
log "LaunchPilot demo: build + QA for bundled $PRODUCT"
bash "$LP_DIR/scripts/build.sh" "$PRODUCT"
job_dir="$(new_job_dir "$PRODUCT")"
bash "$LP_DIR/scripts/qa.sh" "$PRODUCT" "$job_dir"
ok "Demo passed — build + visual QA capture (see $job_dir)"
