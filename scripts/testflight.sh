#!/usr/bin/env bash
# Bump build number and upload an app to TestFlight via kits/testflight.
# Gated: requires --confirm. Never runs as part of an unattended pipeline.
#   testflight.sh <product> --confirm
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: testflight.sh <product> --confirm}"

if [[ "$P_TYPE" != "app" ]]; then
  err "$P_NAME is not an app"
  exit 1
fi
if [[ "${2:-}" != "--confirm" ]]; then
  err "TestFlight upload is gated. Re-run with --confirm to proceed."
  err "  ./bin/pilot testflight $1 --confirm"
  exit 1
fi
if [[ ! -f "$TF_KIT/config.sh" ]]; then
  err "kits/testflight/config.sh missing — see docs/SETUP.md"
  exit 1
fi
if [[ ! -f "$TF_KIT/apps.sh" ]]; then
  err "kits/testflight/apps.sh missing — copy from apps.example.sh (docs/SETUP.md)"
  exit 1
fi

log "Bumping build number for $P_NAME"
"$TF_KIT/bump-build.sh" "$P_TF_KEY"

log "Archiving + uploading $P_NAME to TestFlight"
"$TF_KIT/archive-and-upload.sh" "$P_TF_KEY"
ok "$P_NAME submitted to TestFlight (processing on Apple's side)"

# GitHub Release + CHANGELOG so every TF build has a revert/fix ledger.
RN_KIT="$LP_DIR/kits/release-notes"
if [[ -x "$RN_KIT/publish.sh" ]]; then
  VERSION="$(cd "$REPO_DIR" && (agvtool what-marketing-version -terse1 2>/dev/null || true))"
  BUILD="$(cd "$REPO_DIR" && (agvtool what-version -terse 2>/dev/null || true))"
  if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    # Fallback: Info.plist / project — still publish a dated tag
    VERSION="${VERSION:-0.0.0}"
    BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
  fi
  TAG="${P_TF_KEY}-ios-${VERSION}+${BUILD}"
  log "Publishing release notes tag $TAG"
  "$RN_KIT/publish.sh" --repo "$REPO_DIR" --tag "$TAG" --title "$P_NAME $VERSION ($BUILD)" --commit || \
    warn "release notes publish failed (TestFlight upload already succeeded)"
fi
