#!/usr/bin/env bash
# Shared helpers + per-app config for the TestFlight kit (inside LaunchPilot).
# Sourced by the other scripts; not meant to be run directly.

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

# --- Resolve per-app project metadata -------------------------------------
# Usage: resolve_app <key>
# Apps are defined in apps.sh (gitignored). Copy from apps.example.sh.
resolve_app() {
  if [[ ! -f "$KIT_DIR/apps.sh" ]]; then
    echo "ERROR: $KIT_DIR/apps.sh not found." >&2
    echo "Copy apps.example.sh to apps.sh and add your Xcode projects." >&2
    return 1
  fi
  # shellcheck disable=SC1091
  source "$KIT_DIR/apps.sh"
  if ! declare -F tf_resolve_app >/dev/null; then
    echo "ERROR: apps.sh must define tf_resolve_app <key>" >&2
    return 1
  fi
  tf_resolve_app "${1:-}"
  PBXPROJ="$PROJECT/project.pbxproj"
}

# --- Load user secrets/config ---------------------------------------------
load_config() {
  if [[ -f "$KIT_DIR/config.sh" ]]; then
    # shellcheck disable=SC1091
    source "$KIT_DIR/config.sh"
  else
    echo "ERROR: $KIT_DIR/config.sh not found." >&2
    echo "Copy config.example.sh to config.sh and fill in your values." >&2
    return 1
  fi

  : "${TEAM_ID:?Set TEAM_ID in config.sh}"
  : "${ASC_KEY_ID:?Set ASC_KEY_ID in config.sh}"
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID in config.sh}"
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH in config.sh}"

  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "ERROR: API key file not found at: $ASC_KEY_PATH" >&2
    return 1
  fi
}

log() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m!\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
