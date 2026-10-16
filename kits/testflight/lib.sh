#!/usr/bin/env bash
# Shared helpers + per-app config for the TestFlight kit (inside LaunchPilot).
# Sourced by the other scripts; not meant to be run directly.
#
# Local (gitignored) files this kit reads, first match wins:
#   app registry : apps.local.sh  → apps.sh      (template: apps.example.sh)
#   credentials  : config.local.sh → config.sh   (template: config.example.sh)
# Override either path with TF_APPS_FILE / TF_CONFIG_FILE.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LaunchPilot root is two levels up from kits/testflight
LP_DIR="$(cd "$KIT_DIR/../.." && pwd)"

# Product repos live in the workspace (parent of LaunchPilot by default).
# Override with PILOT_WORKSPACE (shell or LaunchPilot config/pilot.env).
if [[ -f "$LP_DIR/config/pilot.env" ]]; then
  # shellcheck disable=SC1091
  source "$LP_DIR/config/pilot.env" 2>/dev/null || true
fi
WORKSPACE="${PILOT_WORKSPACE:-$(cd "$LP_DIR/.." && pwd)}"
# Back-compat name used throughout this kit
DESKTOP="$WORKSPACE"

_first_existing() {
  local f
  for f in "$@"; do
    [[ -n "$f" && -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

tf_apps_file() {
  _first_existing "${TF_APPS_FILE:-}" "$KIT_DIR/apps.local.sh" "$KIT_DIR/apps.sh"
}

tf_config_file() {
  _first_existing "${TF_CONFIG_FILE:-}" "$KIT_DIR/config.local.sh" "$KIT_DIR/config.sh"
}

_source_apps() {
  local f
  if ! f="$(tf_apps_file)"; then
    echo "ERROR: no app registry found (apps.local.sh or apps.sh in $KIT_DIR)." >&2
    echo "Copy apps.example.sh to apps.local.sh and add your Xcode projects." >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$f"
  if ! declare -F tf_resolve_app >/dev/null; then
    echo "ERROR: $f must define tf_resolve_app <key>" >&2
    return 1
  fi
}

# --- Resolve per-app project metadata -------------------------------------
# Usage: resolve_app <key>
resolve_app() {
  _source_apps
  # Reset optional per-app fields so one app never inherits another's values.
  WATCH_BUNDLE_ID="" WATCH_PROFILE_NAME="" BETA_GROUP_ID="" EXTERNAL_BETA_GROUP_IDS="${TF_EXTERNAL_BETA_GROUP_IDS:-}"
  tf_resolve_app "${1:-}"
  : "${APP_KEY:?apps registry: APP_KEY not set for '${1:-}'}"
  : "${PROJECT:?apps registry: PROJECT not set for '${1:-}'}"
  : "${SCHEME:?apps registry: SCHEME not set for '${1:-}'}"
  PBXPROJ="$PROJECT/project.pbxproj"
}

# Space-separated list of every app key in the registry. Uses TF_APP_KEYS when
# the registry sets it, otherwise the case labels of tf_resolve_app.
tf_app_keys() {
  _source_apps
  if [[ -n "${TF_APP_KEYS:-}" ]]; then
    echo "$TF_APP_KEYS"
    return 0
  fi
  local f
  f="$(tf_apps_file)"
  grep -E '^[[:space:]]+[A-Za-z0-9_-]+\)[[:space:]]*$' "$f" | tr -d ' )\t' | tr '\n' ' '
}

# --- Load user secrets/config ---------------------------------------------
load_config() {
  local f
  if ! f="$(tf_config_file)"; then
    echo "ERROR: no credentials file found (config.local.sh or config.sh in $KIT_DIR)." >&2
    echo "Copy config.example.sh to config.local.sh and fill in your values." >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$f"

  : "${TEAM_ID:?Set TEAM_ID in $f}"
  : "${ASC_KEY_ID:?Set ASC_KEY_ID in $f}"
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID in $f}"
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH in $f}"

  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "ERROR: API key file not found at: $ASC_KEY_PATH" >&2
    return 1
  fi
}

# Show that a value is set without printing it.
mask() { local v="${1:-}"; [[ -n "$v" ]] && printf 'set (%d chars)' "${#v}" || printf 'NOT SET'; }

log() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m!\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
