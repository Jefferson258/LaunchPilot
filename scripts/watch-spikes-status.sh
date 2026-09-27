#!/usr/bin/env bash
# Safely report whether the error-spike watcher is installed and loaded.
#   watch-spikes-status.sh [--require-running]
set -euo pipefail

LP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.launchpilot.watch-spikes"
DOMAIN="gui/$(id -u)"
PLIST="${PILOT_WATCH_PLIST:-$HOME/Library/LaunchAgents/$LABEL.plist}"
LOG_DIR="${PILOT_WATCH_LOG_DIR:-$LP_DIR/jobs/alerts}"
REQUIRE_RUNNING=0

case "${1:-}" in
  "") ;;
  -h|--help)
    printf 'usage: watch-spikes-status.sh [--require-running]\n'
    exit 0
    ;;
  --require-running) REQUIRE_RUNNING=1 ;;
  *) printf 'usage: watch-spikes-status.sh [--require-running]\n' >&2; exit 2 ;;
esac

ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

failed=0
printf 'LaunchPilot error-spike watcher (%s)\n' "$LABEL"

if [[ ! -f "$PLIST" ]]; then
  err "plist not installed: $PLIST"
  failed=1
else
  if plutil -lint "$PLIST" >/dev/null 2>&1; then
    ok "plist present and valid: $PLIST"
  else
    err "plist is invalid: $PLIST"
    failed=1
  fi
fi

if [[ ! -d "$LOG_DIR" ]]; then
  err "watcher log directory is missing: $LOG_DIR"
  err "  create it before bootstrapping: mkdir -p \"$LOG_DIR\""
  failed=1
elif [[ ! -w "$LOG_DIR" ]]; then
  err "watcher log directory is not writable: $LOG_DIR"
  failed=1
else
  ok "watcher log directory is writable: $LOG_DIR"
fi

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v launchctl >/dev/null 2>&1; then
  err "launchd is unavailable on this host"
  exit 1
fi

SERVICE_INFO="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null || true)"
if [[ -n "$SERVICE_INFO" ]]; then
  ok "launchd service loaded: $DOMAIN/$LABEL"
else
  err "launchd service is not loaded: $DOMAIN/$LABEL"
  err "  load it with: launchctl bootstrap $DOMAIN \"$PLIST\""
  failed=1
fi

last_exit="$(printf '%s\n' "$SERVICE_INFO" | awk -F'= ' '/last exit code/{print $2; exit}')"
if [[ "$last_exit" =~ ^[1-9][0-9]*$ ]]; then
  err "last watcher invocation failed (exit $last_exit)"
  err "  inspect: $LOG_DIR/watch-spikes.err"
  failed=1
fi

pid="$(launchctl list "$LABEL" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { print $1; exit }' || true)"
if [[ -n "$pid" ]]; then
  ok "watcher process is running (PID $pid)"
elif [[ "$REQUIRE_RUNNING" == "1" ]]; then
  err "watcher process is not running right now"
  failed=1
else
  warn "watcher is loaded but idle (normal between 15-minute runs)"
fi

for file in "$LOG_DIR/watch-spikes.log" "$LOG_DIR/watch-spikes.err"; do
  if [[ -f "$file" ]]; then
    modified="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %Z' "$file" 2>/dev/null || printf 'unknown')"
    printf '  log %s (last modified %s)\n' "$file" "$modified"
  else
    printf '  log not created yet: %s\n' "$file"
  fi
done

exit "$failed"
