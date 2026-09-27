#!/usr/bin/env bash
# Phone / SSH entrypoint: keep Mac awake, run LaunchPilot, then sleep or shut down.
#
# Intended to be invoked over SSH from an iPhone Shortcut (or Cursor Remote Control):
#   ~/Desktop/LaunchPilot/bin/pilot remote-run <product> "<prompt>" [--ship…] [--sleep|--shutdown]
#
# Default power action after a successful pipeline: --sleep (wakeable again on this Mac).
# Use --shutdown only when you mean fully off (M4 + smart-plug path can power-cycle back).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

usage() {
  cat <<'EOF'
Usage: pilot remote-run <product> "<prompt>" [options]

  Runs the full LaunchPilot pipeline while holding the Mac awake (caffeinate),
  then optionally sleeps or shuts down.

Options (same ship flags as `pilot run`):
  --ship-preview | --ship-prod | --ship-testflight | --ship-appstore | --ship
  (--ship never implies App Store submit; do not put --ship-appstore in Shortcuts
   unless the owner explicitly asked for a real ASC submit.)

Power after success (pick one; default --sleep):
  --sleep       pmset sleepnow (recommended on M2 / sleep-wake path)
  --shutdown    sudo shutdown -h now (needs passwordless sudo OR interactive tty)
  --stay-awake  do not sleep/shutdown when finished

Other:
  --allow-fail-power   still sleep/shutdown even if the pipeline failed
  -h, --help
EOF
}

PRODUCT=""
PROMPT=""
SHIP_ARGS=()
POWER="sleep"
ALLOW_FAIL_POWER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ship-preview|--ship-prod|--ship-testflight|--ship-appstore|--ship) SHIP_ARGS+=("$1"); shift ;;
    --sleep) POWER="sleep"; shift ;;
    --shutdown) POWER="shutdown"; shift ;;
    --stay-awake) POWER="stay"; shift ;;
    --allow-fail-power) ALLOW_FAIL_POWER=1; shift ;;
    --*)
      err "unknown flag: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$PRODUCT" ]]; then
        PRODUCT="$1"
      elif [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      else
        err "unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$PRODUCT" || -z "$PROMPT" ]]; then
  usage
  exit 1
fi

log "Remote run: product=$PRODUCT power_after=$POWER"
ok "host $(scutil --get ComputerName 2>/dev/null || hostname) — $(date)"

# Phone runs should fail closed on missing QA unless explicitly relaxed.
export PILOT_QA_STRICT="${PILOT_QA_STRICT:-1}"

CAFFEINE_PID=""
cleanup_caffeine() {
  if [[ -n "$CAFFEINE_PID" ]] && kill -0 "$CAFFEINE_PID" 2>/dev/null; then
    kill "$CAFFEINE_PID" 2>/dev/null || true
  fi
}
trap cleanup_caffeine EXIT

if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dims &
  CAFFEINE_PID=$!
  ok "caffeinate started (pid $CAFFEINE_PID)"
else
  warn "caffeinate not found — Mac may re-sleep during the run"
fi

PIPELINE_STATUS=0
set +e
run_pipeline "$PRODUCT" "$PROMPT" "${SHIP_ARGS[@]+"${SHIP_ARGS[@]}"}"
PIPELINE_STATUS=$?
set -e

if [[ "$PIPELINE_STATUS" -ne 0 ]]; then
  err "pipeline exited $PIPELINE_STATUS"
  bash "$LP_DIR/scripts/notify.sh" "Remote run FAILED ($PRODUCT): exit $PIPELINE_STATUS" "" "LaunchPilot failed" || true
  if [[ "$ALLOW_FAIL_POWER" != "1" ]]; then
    warn "skipping power action (pass --allow-fail-power to sleep/shutdown anyway)"
    exit "$PIPELINE_STATUS"
  fi
fi

cleanup_caffeine
trap - EXIT

case "$POWER" in
  stay)
    ok "staying awake (--stay-awake)"
    ;;
  sleep)
    log "Sleeping Mac now (wake again via network / SSH)"
    # Give SSH a moment to flush output
    ( sleep 2; pmset sleepnow ) &
    ok "sleep scheduled"
    ;;
  shutdown)
    log "Shutting down Mac now"
    if sudo -n true 2>/dev/null; then
      ( sleep 2; sudo shutdown -h now ) &
      ok "shutdown scheduled (passwordless sudo)"
    else
      err "shutdown needs passwordless sudo for non-interactive SSH"
      err "  e.g. sudoers: $USER ALL=(ALL) NOPASSWD: /sbin/shutdown"
      err "  or run interactively / use --sleep instead"
      exit 1
    fi
    ;;
esac

if [[ "$PIPELINE_STATUS" -eq 0 ]]; then
  bash "$LP_DIR/scripts/notify.sh" "Remote run OK ($PRODUCT)" "" "LaunchPilot done" || true
fi

exit "$PIPELINE_STATUS"
