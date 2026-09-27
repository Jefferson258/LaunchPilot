#!/usr/bin/env bash
# Run the Cursor agent (SDK) against a product repo on a fresh branch.
#   code.sh <product> "<prompt>" [job_dir]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: code.sh <product> \"<prompt>\" [job_dir]}"
PROMPT="${2:?provide a prompt}"
JOB_DIR="${3:-$(new_job_dir "$1")}"

if [[ -z "${CURSOR_API_KEY:-}" ]]; then
  err "CURSOR_API_KEY is not set — add it to config/pilot.env"
  err "  create one at https://cursor.com/dashboard/integrations"
  exit 1
fi
if [[ ! -d "$LP_DIR/agent/node_modules/@cursor/sdk" ]]; then
  err "@cursor/sdk not installed — run: (cd $LP_DIR/agent && npm install)"
  exit 1
fi

cd "$REPO_DIR"
if [[ -n "$(git status --porcelain)" ]]; then
  err "product repo has uncommitted changes: $REPO_DIR"
  err "commit/stash them before starting a Pilot coding run"
  exit 1
fi
BRANCH="pilot/$1/$(date +%Y%m%d-%H%M%S)"
log "Creating branch $BRANCH in $P_REPO"
git checkout -b "$BRANCH"

log "Dispatching Cursor agent for $P_NAME"
printf '%s\n' "$PROMPT" > "$JOB_DIR/prompt.txt"
PILOT_REPO_DIR="$REPO_DIR" \
PILOT_PROMPT="$PROMPT" \
PILOT_JOB_DIR="$JOB_DIR" \
PILOT_MODEL="${PILOT_MODEL:-auto}" \
  node "$LP_DIR/agent/run-agent.mjs"

echo "$BRANCH" > "$JOB_DIR/branch.txt"
ok "agent run complete on $BRANCH (evidence in $JOB_DIR)"
