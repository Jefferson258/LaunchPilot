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
    juicd)
      APP_KEY="juicd"
      APP_DISPLAY="Juicd"
      PROJECT="$DESKTOP/juicd/Juicd.xcodeproj"
      SCHEME="Juicd"
      BUNDLE_ID="com.jefferson258.juicd"
      PROFILE_NAME="Juicd AppStore"
      ASC_APP_ID="6785327494"
      BETA_GROUP_ID="00000000-0000-0000-0000-000000000000"
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    velour)
      APP_KEY="velour"
      APP_DISPLAY="Velour Closet"
      PROJECT="$DESKTOP/VelourCloset/VelourCloset.xcodeproj"
      SCHEME="VelourCloset"
      BUNDLE_ID="com.velour.VelourCloset"
      PROFILE_NAME="Velour AppStore"
      ASC_APP_ID="6785327329"
      BETA_GROUP_ID="00000000-0000-0000-0000-000000000000"
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    corvim)
      APP_KEY="corvim"
      APP_DISPLAY="Corvim"
      PROJECT="$DESKTOP/Corvim/Corvim.xcodeproj"
      SCHEME="Corvim"
      BUNDLE_ID="com.corvim.Corvim"
      PROFILE_NAME="Corvim AppStore"
      WATCH_BUNDLE_ID="com.corvim.Corvim.watchkitapp"
      WATCH_PROFILE_NAME="Corvim Watch AppStore"
      ASC_APP_ID="6760210188"
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
