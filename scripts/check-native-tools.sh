#!/usr/bin/env bash
# Warn when pipeline CLIs are Intel-only (Rosetta) on Apple silicon.
# Apple: Rosetta remains through macOS 27; limited in macOS 28+.
# https://support.apple.com/en-us/102527
set -euo pipefail

arch_name() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  file "$bin" 2>/dev/null | sed -n 's/.*: //p'
}

is_rosetta_only() {
  local info
  info="$(arch_name "$1")"
  [[ "$info" == *"x86_64"* && "$info" != *"arm64"* && "$info" != *"universal"* ]]
}

warn=0
if [[ "$(uname -m)" != "arm64" ]]; then
  exit 0
fi

check() {
  local name="$1"
  local bin
  bin="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$bin" ]] || return 0
  if is_rosetta_only "$bin"; then
    printf '! %s — Intel (Rosetta): %s\n' "$name" "$bin"
    warn=1
  else
    printf '✓ %s — native/universal: %s\n' "$name" "$(arch_name "$bin")"
  fi
}

echo "Apple silicon toolchain check (Rosetta sunset: macOS 28+)"
check git
check gh
check node
check python3

if [[ "$warn" -eq 1 ]]; then
  echo
  echo "Fix: brew install git gh  (Apple Silicon Homebrew: /opt/homebrew)"
  echo "Then put /opt/homebrew/bin before /usr/local/bin in PATH."
  echo "See LaunchCommandCenter/AGENT_SETUP.md § Apple silicon / Rosetta"
  exit 1
fi
