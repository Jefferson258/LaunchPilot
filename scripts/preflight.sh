#!/usr/bin/env bash
# Print a readiness report: tools, auth, config, and per-product repo presence.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

status() { # name, ok(0/1), detail
  if [[ "$2" == "1" ]]; then ok "$1 — $3"; else warn "$1 — $3"; fi
}

log "Workspace"
ok "root — $DESKTOP${PILOT_WORKSPACE:+ (PILOT_WORKSPACE)}"

log "Tooling"
command -v node       >/dev/null 2>&1 && status "node" 1 "$(node --version)"        || status "node" 0 "not found"
command -v git        >/dev/null 2>&1 && status "git" 1 "present"                    || status "git" 0 "not found"
command -v gh         >/dev/null 2>&1 && status "gh" 1 "present"                      || status "gh" 0 "not found (push/PR)"
command -v xcodebuild >/dev/null 2>&1 && status "xcodebuild" 1 "present"             || status "xcodebuild" 0 "not found (apps)"
command -v vercel     >/dev/null 2>&1 && status "vercel" 1 "present"                  || status "vercel" 0 "not found (web deploy)"

log "Apple silicon / Rosetta"
_NATIVE_CHECK=""
if [[ -x "$LP_DIR/scripts/check-native-tools.sh" ]]; then
  _NATIVE_CHECK="$LP_DIR/scripts/check-native-tools.sh"
elif [[ -x "$DESKTOP/scripts/check-native-tools.sh" ]]; then
  _NATIVE_CHECK="$DESKTOP/scripts/check-native-tools.sh"
fi
if [[ "$(uname -m)" == "arm64" ]] && [[ -n "$_NATIVE_CHECK" ]]; then
  if "$_NATIVE_CHECK" >/tmp/pilot-native-tools.txt 2>&1; then
    ok "CLI tools are native or universal (no Rosetta-only git/gh)"
  else
    warn "Intel-only CLI tools detected — pipeline may break on macOS 28+"
    sed 's/^/  /' /tmp/pilot-native-tools.txt
    echo "  Fix: brew install git gh; put /opt/homebrew/bin before /usr/local/bin"
    echo "  https://support.apple.com/en-us/102527"
  fi
fi

log "Auth / credentials"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  status "GitHub" 1 "$(gh auth status 2>&1 | grep -m1 'Logged in' | sed 's/^ *//')"
else
  status "GitHub" 0 "not authenticated (gh auth login)"
fi
[[ -n "${CURSOR_API_KEY:-}" ]] && status "CURSOR_API_KEY" 1 "set"                    || status "CURSOR_API_KEY" 0 "missing (coding step)"
[[ -n "${VERCEL_TOKEN:-}" ]]   && status "VERCEL_TOKEN" 1 "set"                       || status "VERCEL_TOKEN" 0 "missing (web deploy)"
[[ -f "$TF_KIT/config.sh" ]] && status "kits/testflight/config.sh" 1 "present" || status "kits/testflight/config.sh" 0 "missing (uploads — docs/SETUP.md)"
[[ -f "$TF_KIT/apps.sh" ]] && status "kits/testflight/apps.sh" 1 "present" || status "kits/testflight/apps.sh" 0 "missing (copy apps.example.sh)"

log "Cursor SDK"
if [[ -d "$LP_DIR/agent/node_modules/@cursor/sdk" ]]; then
  status "@cursor/sdk" 1 "installed"
else
  status "@cursor/sdk" 0 "not installed (cd agent && npm install)"
fi

log "Products / repos"
while IFS= read -r product; do
  [[ -z "$product" ]] && continue
  if resolve_product "$product" >/dev/null 2>&1; then
    ok "$product — $P_REPO"
  else
    warn "$product — repo missing"
  fi
done < <(list_products)

log "Config files"
[[ -f "$LP_DIR/config/pilot.env" ]] && status "config/pilot.env" 1 "present" || status "config/pilot.env" 0 "copy from pilot.env.example"
[[ -f "$LP_DIR/config/products.json" ]] && status "config/products.json" 1 "present" || status "config/products.json" 0 "copy from products.example.json"
[[ -d "$LP_DIR/examples/demo-site" ]] && status "bundled demo" 1 "run: ./bin/pilot demo" || status "bundled demo" 0 "examples/demo-site missing"
