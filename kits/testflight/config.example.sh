#!/usr/bin/env bash
# Copy this file to config.local.sh (or config.sh) and fill in your values.
#   cp config.example.sh config.local.sh
# Both names are gitignored so your keys never get committed.
#
# Full walkthrough: ../../docs/SETUP.md

# Your Apple Developer Team ID
#   developer.apple.com/account → Membership details → Team ID
export TEAM_ID="YOUR_TEAM_ID"

# --- App Store Connect API key (create once) ------------------------------
# appstoreconnect.apple.com → Users and Access → Integrations → Keys
#   1. Generate a key with at least the "App Manager" role.
#   2. Note Key ID + Issuer ID.
#   3. Download the .p8 once; store outside the repo (recommended path below).
export ASC_KEY_ID="XXXXXXXXXX"
export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8"

# --- TestFlight group attach (optional) ------------------------------------
# post-upload.sh always attaches builds to internal groups. To also attach to
# external groups for every app, list their ids here (or per app in the
# registry via EXTERNAL_BETA_GROUP_IDS). Leave empty for internal only.
# export TF_EXTERNAL_BETA_GROUP_IDS=""
