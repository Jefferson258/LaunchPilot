#!/usr/bin/env bash
# Notification sink: log file + optional ntfy push (PILOT_NTFY_TOPIC in pilot.env).
#   notify.sh "<message>" [job_dir] [title]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
MESSAGE="${1:?usage: notify.sh \"<message>\" [job_dir] [title]}"
JOB_DIR="${2:-}"
TITLE="${3:-LaunchPilot}"

stamp="$(date '+%Y-%m-%d %H:%M:%S')"
printf '[%s] %s\n' "$stamp" "$MESSAGE"
[[ -n "$JOB_DIR" ]] && printf '[%s] %s\n' "$stamp" "$MESSAGE" >> "$JOB_DIR/log.txt"

topic="${PILOT_NTFY_TOPIC:-}"
if [[ -n "$topic" ]]; then
  if command -v curl >/dev/null 2>&1; then
    curl -sfS -H "Title: $TITLE" -H "Priority: default" -H "Tags: rocket" \
      -d "$MESSAGE" "https://ntfy.sh/$topic" >/dev/null \
      || warn "ntfy push failed (topic=$topic)"
  else
    warn "curl missing — skipped ntfy push"
  fi
fi

if [[ "${PILOT_NOTION_ENABLED:-0}" == "1" ]]; then
  warn "PILOT_NOTION_ENABLED=1: have the agent post this to Notion via MCP"
fi
