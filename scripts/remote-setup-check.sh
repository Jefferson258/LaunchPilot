#!/usr/bin/env bash
# Print readiness for phone → Mac remote LaunchPilot (sleep-wake and/or M4 cold-boot).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

status() {
  if [[ "$2" == "1" ]]; then ok "$1 — $3"; else warn "$1 — $3"; fi
}

log "Remote phone → Mac readiness"

MODEL="$(sysctl -n hw.model 2>/dev/null || true)"
if [[ -z "$MODEL" || "$MODEL" == "unknown" ]]; then
  MODEL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/{print $2; exit}')"
fi
MODEL="${MODEL:-unknown}"
CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
if [[ -z "$CHIP" ]]; then
  CHIP="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip:/{print $2; exit}')"
fi
CHIP="${CHIP:-unknown}"
VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
ok "Mac — model=$MODEL chip=$CHIP macOS=$VER"

# Rough eligibility for Apple "Start up when power is connected → Always"
# (Mac mini 2024+/Mac14,10+ style identifiers vary; we key off known M2 mini Mac14,3 as NOT eligible)
ALWAYS_OK=0
case "$MODEL" in
  Mac16,*|Mac15,*) ALWAYS_OK=1 ;;  # recent desktop families (heuristic)
  Mac14,3) ALWAYS_OK=0 ;;         # M2 Mac mini 2023 — not supported per Apple HT125517
  *) ALWAYS_OK=0 ;;
esac

if [[ "$ALWAYS_OK" == "1" ]]; then
  status "cold-boot (Always + smart plug)" 1 "hardware looks recent — confirm Energy → Start up when power is connected → Always"
else
  status "cold-boot (Always + smart plug)" 0 "this Mac is likely ineligible (need 2024+ mini / 2025+ Studio / 2024+ iMac). Use sleep-wake path."
fi

WOMP="$(pmset -g 2>/dev/null | awk '/womp/{print $2}')"
[[ "$WOMP" == "1" ]] && status "Wake for network access (womp)" 1 "on" || status "Wake for network access (womp)" 0 "off — System Settings → Energy → Wake for network access"

SSH_OK=0
SSH_DETAIL="enable System Settings → General → Sharing → Remote Login"
if [[ "$(systemsetup -getremotelogin 2>/dev/null | awk '{print $NF}')" == "On" ]]; then
  SSH_OK=1
  SSH_DETAIL="Remote Login On (systemsetup)"
elif pgrep -x sshd >/dev/null 2>&1; then
  SSH_OK=1
  SSH_DETAIL="sshd process present"
elif nc -z 127.0.0.1 22 >/dev/null 2>&1 || nc -z localhost 22 >/dev/null 2>&1; then
  SSH_OK=1
  SSH_DETAIL="port 22 accepting connections"
elif launchctl print system/com.openssh.sshd 2>/dev/null | grep -q "state = running"; then
  SSH_OK=1
  SSH_DETAIL="com.openssh.sshd running"
fi
status "Remote Login (SSH)" "$SSH_OK" "$SSH_DETAIL"

if command -v caffeinate >/dev/null 2>&1; then
  status "caffeinate" 1 "present"
else
  status "caffeinate" 0 "missing"
fi

if sudo -n true 2>/dev/null; then
  status "passwordless sudo (shutdown)" 1 "ok for --shutdown over SSH"
else
  status "passwordless sudo (shutdown)" 0 "needed only for --shutdown; --sleep works without it"
fi

IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
[[ -z "$IP" ]] && IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
if [[ -z "$IP" ]]; then
  IP="$(ifconfig en0 2>/dev/null | awk '/inet /{print $2; exit}')"
fi
if [[ -z "$IP" ]]; then
  IP="$(ifconfig en1 2>/dev/null | awk '/inet /{print $2; exit}')"
fi
IP="${IP:-?}"
ok "LAN IP (for Shortcuts SSH) — $IP"
ok "SSH one-liner template:"
echo "  ssh $USER@$IP '~/Desktop/LaunchPilot/bin/pilot remote-run demo-site \"Smoke from phone\" --sleep'"

echo
log "Paths"
echo "  Sleep-wake (this Mac):  docs/PHONE.md → Path A"
echo "  M4 cold-boot:           docs/PHONE.md → Path B"
echo "  Shortcut recipes:       docs/shortcuts-iphone.md"
