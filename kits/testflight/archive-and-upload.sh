#!/usr/bin/env bash
# Archive an app for distribution and upload it to TestFlight, fully from the
# command line, using an App Store Connect API key (no interactive Apple login).
#
#   ./archive-and-upload.sh <app-key>
#   ./archive-and-upload.sh <app-key> --dry-run   # resolve config, print plan, exit
#
# Requirements (one-time, done by YOU — see README.md):
#   - config.local.sh (or config.sh) filled in (Team ID + API key details)
#   - apps.local.sh (or apps.sh) with a case for <app-key>
#   - The App ID/bundle registered and the app record created in
#     App Store Connect (the build needs an app to attach to).
#
# Signing is handled automatically via the API key (-allowProvisioningUpdates),
# so Xcode will create/download the distribution certificate and provisioning
# profile for you the first time.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DRY_RUN="${TF_DRY_RUN:-0}"
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
resolve_app "${POSITIONAL[0]:?Usage: ./archive-and-upload.sh <app-key> [--dry-run]  (keys: $(tf_app_keys))}"
load_config

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY RUN — $APP_DISPLAY ($APP_KEY): nothing will be archived or uploaded"
  echo "  registry   : $(tf_apps_file)"
  echo "  credentials: $(tf_config_file)"
  echo "  project    : $PROJECT $([[ -d "$PROJECT" ]] && echo '(found)' || echo '(MISSING)')"
  echo "  scheme     : $SCHEME"
  echo "  bundle id  : ${BUNDLE_ID:-NOT SET}"
  echo "  profile    : ${PROFILE_NAME:-NOT SET}"
  [[ -n "${WATCH_BUNDLE_ID:-}" ]] && echo "  watch      : $WATCH_BUNDLE_ID → ${WATCH_PROFILE_NAME:-NOT SET}"
  echo "  ASC app id : $(mask "${ASC_APP_ID:-}")"
  echo "  team id    : $(mask "$TEAM_ID")"
  echo "  ASC key    : id $(mask "$ASC_KEY_ID"), issuer $(mask "$ASC_ISSUER_ID"), .p8 present"
  [[ -f "$PBXPROJ" ]] && echo "  build num  : $(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ" | grep -oE '[0-9]+' || echo '?')"
  "$(dirname "${BASH_SOURCE[0]}")/post-upload.sh" "$APP_KEY" --dry-run
  exit 0
fi

ARCHIVE_PATH="/tmp/${APP_KEY}.xcarchive"
EXPORT_DIR="/tmp/${APP_KEY}-export"
EXPORT_OPTS="/tmp/${APP_KEY}-ExportOptions.plist"

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

# Apps with an embedded watch app need its own provisioning profile.
EXTRA_PROFILES=""
if [[ -n "${WATCH_BUNDLE_ID:-}" ]]; then
  EXTRA_PROFILES="    <key>${WATCH_BUNDLE_ID}</key><string>${WATCH_PROFILE_NAME}</string>"
fi

# Build ExportOptions.plist on the fly so the Team ID comes from local config.
# We use MANUAL signing with a pre-created Apple Distribution certificate and
# App Store provisioning profile, because an API key with the
# "App Manager" role, which Apple forbids from using cloud-managed distribution
# certificates. The cert + profiles are created via the App Store Connect API
# (see make-signing-assets.sh) and installed locally.
cat > "$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key><string>upload</string>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string>
${EXTRA_PROFILES}
  </dict>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

log "Archiving $APP_DISPLAY (Release)…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID"

log "Exporting + uploading $APP_DISPLAY to TestFlight…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

log "$APP_DISPLAY uploaded ✅"
echo "It will appear in App Store Connect -> TestFlight in a few minutes"
echo "(after Apple finishes processing the build)."

log "Running post-upload automation (compliance check + internal testers + optional external groups)…"
BUILD_NUM="$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ" | grep -oE '[0-9]+')"
"$(dirname "${BASH_SOURCE[0]}")/post-upload.sh" "$APP_KEY" "$BUILD_NUM"
