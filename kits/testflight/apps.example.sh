#!/usr/bin/env bash
# App registry template. Copy and edit for your products:
#   cp apps.example.sh apps.local.sh      # (apps.sh also works)
# apps.local.sh / apps.sh are gitignored — never commit real IDs.
#
# Each case must set at least:
#   APP_KEY, APP_DISPLAY, PROJECT, SCHEME, BUNDLE_ID, PROFILE_NAME,
#   ASC_APP_ID, SIM_DEST
# Optional:
#   WATCH_BUNDLE_ID, WATCH_PROFILE_NAME   embedded watchOS app (own profile)
#   EXTERNAL_BETA_GROUP_IDS               space-separated external TestFlight
#                                         group ids that post-upload.sh should
#                                         also attach builds to. Empty (the
#                                         default) = internal testers only.
#   BETA_GROUP_ID                         legacy single external group; only
#                                         used when TF_ATTACH_EXTERNAL=1.
#
# PROJECT paths are under PILOT_WORKSPACE (default: parent of LaunchPilot).

# Keys used by `build-check.sh all` and make-signing-assets.sh.
TF_APP_KEYS="example"

tf_resolve_app() {
  case "${1:-}" in
    example)
      APP_KEY="example"
      APP_DISPLAY="Example App"
      PROJECT="$DESKTOP/ExampleApp/ExampleApp.xcodeproj"
      SCHEME="ExampleApp"
      BUNDLE_ID="com.example.app"
      PROFILE_NAME="Example App AppStore"
      ASC_APP_ID="0000000000"
      EXTERNAL_BETA_GROUP_IDS=""
      SIM_DEST="generic/platform=iOS Simulator"
      # WATCH_BUNDLE_ID="com.example.app.watchkitapp"
      # WATCH_PROFILE_NAME="Example App Watch AppStore"
      ;;
    *)
      echo "ERROR: unknown app '${1:-}'. Known: ${TF_APP_KEYS}. Edit kits/testflight/apps.local.sh." >&2
      return 1
      ;;
  esac
}
