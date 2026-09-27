#!/usr/bin/env bash
# Process one intake job at a time.
#   dispatch.sh [--retry-failed|--recover-running|--recover-lock]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"
load_env

INBOX="$LP_DIR/intake/inbox.md"
LOCK_DIR="${PILOT_DISPATCH_LOCK_DIR:-$JOBS_DIR/dispatch.lock}"
LOCK_OWNER="$LOCK_DIR/owner"
LOCK_ATTEMPTS="${PILOT_DISPATCH_LOCK_ATTEMPTS:-3}"
LOCK_DELAY_SEC="${PILOT_DISPATCH_LOCK_DELAY_SEC:-2}"
ACTION="next"
LOCK_HELD=0

usage() {
  cat <<'EOF'
usage: dispatch.sh [--retry-failed|--recover-running|--recover-lock]

  (default)          Dispatch the first pending inbox job.
  --retry-failed     Requeue and dispatch the first # failed (...) job.
  --recover-running  Requeue and dispatch the first # running: job left by a
                     crashed/interrupted dispatcher. Check no pipeline is
                     still running first.
  --recover-lock     Remove a stale dispatcher lock only when its owner PID is
                     no longer running; does not dispatch a job.
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  --retry-failed) ACTION="retry-failed" ;;
  --recover-running) ACTION="recover-running" ;;
  --recover-lock) ACTION="recover-lock" ;;
  *) err "unknown dispatch option: $1"; usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  err "dispatch accepts one option at most"
  usage >&2
  exit 2
fi

if ! [[ "$LOCK_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  err "PILOT_DISPATCH_LOCK_ATTEMPTS must be a positive integer"
  exit 2
fi
if ! [[ "$LOCK_DELAY_SEC" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  err "PILOT_DISPATCH_LOCK_DELAY_SEC must be a non-negative number"
  exit 2
fi

mkdir -p "$JOBS_DIR"

lock_pid() {
  if [[ -f "$LOCK_OWNER" ]]; then
    awk -F= '$1 == "pid" { print $2; exit }' "$LOCK_OWNER"
  fi
}

release_lock() {
  if [[ "$LOCK_HELD" == "1" ]]; then
    rm -f "$LOCK_OWNER"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

acquire_lock() {
  local attempt pid
  for ((attempt=1; attempt<=LOCK_ATTEMPTS; attempt++)); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      {
        printf 'pid=%s\n' "$$"
        printf 'started=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'host=%s\n' "$(hostname)"
        printf 'inbox=%s\n' "$INBOX"
      } > "$LOCK_OWNER"
      LOCK_HELD=1
      trap release_lock EXIT INT TERM
      return 0
    fi
    pid="$(lock_pid)"
    if [[ "$attempt" -lt "$LOCK_ATTEMPTS" ]]; then
      warn "dispatch lock is busy${pid:+ (PID $pid)} — retrying in ${LOCK_DELAY_SEC}s"
      sleep "$LOCK_DELAY_SEC"
    fi
  done
  pid="$(lock_pid)"
  err "another dispatcher owns $LOCK_DIR${pid:+ (PID $pid)}"
  err "If that process is gone, inspect the owner file and run:"
  err "  ./bin/pilot dispatch --recover-lock"
  return 75
}

recover_lock() {
  if [[ -e "$LOCK_DIR" && ! -d "$LOCK_DIR" ]]; then
    err "dispatch lock path exists but is not a directory: $LOCK_DIR"
    return 1
  fi
  if [[ ! -d "$LOCK_DIR" ]]; then
    ok "no dispatch lock exists"
    return 0
  fi
  if [[ ! -f "$LOCK_OWNER" ]]; then
    err "dispatch lock owner metadata is missing; refusing to remove $LOCK_DIR"
    err "inspect the directory and remove it manually only after confirming no dispatcher is active"
    return 1
  fi
  local pid
  pid="$(lock_pid)"
  if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    err "dispatch lock owner metadata has no valid PID; refusing to remove $LOCK_DIR"
    return 1
  fi
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    err "dispatch lock owner PID $pid is still running; refusing to remove it"
    return 1
  fi
  warn "removing stale dispatch lock${pid:+ for dead PID $pid}"
  rm -f "$LOCK_OWNER"
  if ! rmdir "$LOCK_DIR" 2>/dev/null; then
    err "could not remove $LOCK_DIR; inspect it manually"
    return 1
  fi
  ok "stale dispatch lock removed; retry dispatch explicitly"
}

atomic_replace_line() {
  local line_number="$1"
  local expected="$2"
  local replacement="$3"
  local tmp
  tmp="$(mktemp "$INBOX.tmp.XXXXXX")"
  if ! awk -v n="$line_number" -v expected="$expected" -v replacement="$replacement" '
    NR == n {
      if ($0 != expected) exit 42
      print replacement
      changed = 1
      next
    }
    { print }
    END { if (!changed) exit 43 }
  ' "$INBOX" > "$tmp"; then
    rm -f "$tmp"
    err "inbox changed while dispatching; refusing to rewrite line $line_number"
    return 1
  fi
  mv "$tmp" "$INBOX"
}

select_job() {
  case "$ACTION" in
    next)
      awk '!/^[[:space:]]*(#|$)/ { print NR ":" $0; exit }' "$INBOX"
      ;;
    retry-failed)
      awk '/^[[:space:]]*#[[:space:]]failed[[:space:]]\([0-9][0-9]*\):/ { print NR ":" $0; exit }' "$INBOX"
      ;;
    recover-running)
      awk '/^[[:space:]]*#[[:space:]]running:/ { print NR ":" $0; exit }' "$INBOX"
      ;;
  esac
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

if [[ "$ACTION" == "recover-lock" ]]; then
  recover_lock
  exit $?
fi

if [[ ! -f "$INBOX" ]]; then
  err "no inbox at $INBOX (copy intake/inbox.example.md to intake/inbox.md)"
  exit 1
fi
umask 077
acquire_lock

line="$(select_job)"
if [[ -z "$line" ]]; then
  if [[ "$ACTION" == "next" ]]; then
    ok "inbox empty — nothing to dispatch"
  else
    ok "no matching job to recover"
  fi
  exit 0
fi

lineno="${line%%:*}"
record="${line#*:}"
content="$record"
if [[ "$ACTION" == "retry-failed" ]]; then
  if [[ "$record" =~ ^[[:space:]]*#[[:space:]]failed[[:space:]]\([0-9][0-9]*\):[[:space:]]*(.*)$ ]]; then
    content="${BASH_REMATCH[1]}"
  fi
elif [[ "$ACTION" == "recover-running" ]]; then
  if [[ "$record" =~ ^[[:space:]]*#[[:space:]]running:[[:space:]]*(.*)$ ]]; then
    content="${BASH_REMATCH[1]}"
  fi
fi

product="$(trim "${content%%|*}")"
prompt="$(trim "${content#*|}")"
if [[ -z "$product" || -z "$prompt" ]]; then
  err "malformed job on line $lineno: $record"
  exit 1
fi

if [[ "$ACTION" != "next" ]]; then
  log "Requeueing $ACTION job on line $lineno"
  atomic_replace_line "$lineno" "$record" "$content"
fi

log "Dispatching: $product | $prompt"
# Claim before running so an interruption leaves an explicit recovery marker.
running_record="# running: $content"
atomic_replace_line "$lineno" "$content" "$running_record"

dispatch_log="$JOBS_DIR/dispatch-$(date -u '+%Y%m%d-%H%M%S')-$$.log"
{
  printf 'product=%s\nprompt=%s\nline=%s\nstarted=%s\n' \
    "$product" "$prompt" "$lineno" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '\n'
} > "$dispatch_log"
log "Dispatch log: $dispatch_log"

set +e
"$LP_DIR/bin/pilot" run "$product" "$prompt" 2>&1 | tee -a "$dispatch_log"
rc="${PIPESTATUS[0]}"
set -e

if [[ "$rc" -eq 0 ]]; then
  atomic_replace_line "$lineno" "$running_record" "# done: $content"
  ok "dispatch completed; inbox line $lineno marked done"
else
  atomic_replace_line "$lineno" "$running_record" "# failed ($rc): $content"
  err "dispatch failed with exit $rc; inbox line $lineno marked failed"
  err "Dispatch log: $dispatch_log"
  err "Retry after review: ./bin/pilot dispatch --retry-failed"
fi
exit "$rc"
