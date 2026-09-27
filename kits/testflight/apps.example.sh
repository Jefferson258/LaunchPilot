#!/usr/bin/env bash
# Copy to apps.sh and edit for your products:
#   cp apps.example.sh apps.sh
# apps.sh is gitignored — never commit if you prefer private beta group IDs.
#
# Each case must set at least:
#   APP_KEY, APP_DISPLAY, PROJECT, SCHEME, BUNDLE_ID, PROFILE_NAME,
#   ASC_APP_ID, BETA_GROUP_ID, SIM_DEST
# Optional watch app: WATCH_BUNDLE_ID, WATCH_PROFILE_NAME
#
# PROJECT paths are under PILOT_WORKSPACE (default: parent of LaunchPilot).

tf_resolve_app() {
  case "${1:-}" in
    exampleapp)
      APP_KEY="exampleapp"
      APP_DISPLAY="Example App"
      PROJECT="$DESKTOP/exampleapp/Example App.xcodeproj"
      SCHEME="Example App"
      BUNDLE_ID="com.example.app"
      PROFILE_NAME="Example App AppStore"
      ASC_APP_ID="0000000000"
      BETA_GROUP_ID="00000000-0000-0000-0000-000000000000"
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    demoapp)
      APP_KEY="demoapp"
      APP_DISPLAY="Demo App"
      PROJECT="$DESKTOP/DemoApp/DemoApp.xcodeproj"
      SCHEME="DemoApp"
      BUNDLE_ID="com.example.demoapp"
      PROFILE_NAME="DemoApp AppStore"
      ASC_APP_ID="0000000000"
      BETA_GROUP_ID="00000000-0000-0000-0000-000000000000"
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    sampleapp)
      APP_KEY="sampleapp"
      APP_DISPLAY="Sample App"
      PROJECT="$DESKTOP/Sample App/Sample App.xcodeproj"
      SCHEME="Sample App"
      BUNDLE_ID="com.example.sampleapp"
      PROFILE_NAME="Sample App AppStore"
      WATCH_BUNDLE_ID="com.example.sampleapp.watchkitapp"
      WATCH_PROFILE_NAME="Sample App Watch AppStore"
      ASC_APP_ID="0000000000"
      BETA_GROUP_ID="00000000-0000-0000-0000-000000000000"
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    myapp)
      APP_KEY="myapp"
      APP_DISPLAY="My App"
      PROJECT="$DESKTOP/MyApp/MyApp.xcodeproj"
      SCHEME="MyApp"
      BUNDLE_ID="com.example.MyApp"
      PROFILE_NAME="MyApp AppStore"
      ASC_APP_ID="0000000000"
      BETA_GROUP_ID="00000000-0000-0000-0000-000000000000"
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    *)
      echo "ERROR: unknown app '${1:-}'. Edit kits/testflight/apps.sh (from apps.example.sh)." >&2
      return 1
      ;;
  esac
}
