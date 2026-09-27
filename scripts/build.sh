#!/usr/bin/env bash
# Build / compile-check a product.
#   app  -> kits/testflight/build-check.sh <tf_key>
#   web  -> npm install (if needed) + web_build
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: build.sh <product>}"

if [[ "$P_TYPE" == "app" ]]; then
  require_cmd xcodebuild
  if [[ ! -x "$TF_KIT/build-check.sh" ]]; then
    err "iOS build needs the bundled kit at: $TF_KIT/build-check.sh"
    err "  (optional for web products — try: ./bin/pilot demo)"
    err "  Setup: docs/SETUP.md"
    exit 1
  fi
  log "Compile-checking $P_NAME via TestFlight kit ($P_TF_KEY)"
  "$TF_KIT/build-check.sh" "$P_TF_KEY"
  ok "$P_NAME build check passed"
else
  require_cmd node
  cd "$REPO_DIR"
  if [[ ! -d node_modules ]]; then
    log "Installing deps for $P_NAME"
    npm install
  fi
  log "Building $P_NAME (${P_WEB_BUILD:-npm run build})"
  eval "${P_WEB_BUILD:-npm run build}"
  ok "$P_NAME built"
fi
