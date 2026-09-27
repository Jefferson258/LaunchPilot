#!/usr/bin/env bash
# Commit current changes on the pilot branch, push, and optionally open a PR.
#   release.sh <product> "<message>" [--pr] [job_dir]
# Guardrails: never force-pushes; refuses to act on main/master.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: release.sh <product> \"<message>\" [--pr] [job_dir]}"
MESSAGE="${2:?provide a commit message}"
OPEN_PR=0
JOB_DIR=""
shift 2
for arg in "$@"; do
  case "$arg" in
    --pr) OPEN_PR=1 ;;
    *) JOB_DIR="$arg" ;;
  esac
done

cd "$REPO_DIR"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  err "refusing to commit directly on $BRANCH — run code.sh first to create a pilot/* branch"
  exit 1
fi
if [[ "$BRANCH" != pilot/* ]]; then
  err "refusing to release from non-Pilot branch: $BRANCH"
  err "run code.sh first so changes land on a pilot/* branch"
  exit 1
fi

if git diff --quiet && git diff --cached --quiet; then
  warn "no changes to commit on $BRANCH"
  exit 0
fi

log "Committing on $BRANCH"
git add -A
git commit -m "$MESSAGE"
[[ -n "$JOB_DIR" ]] && git --no-pager diff --stat HEAD~1 > "$JOB_DIR/diffstat.txt" 2>/dev/null || true

log "Pushing $BRANCH"
git push -u origin "$BRANCH"
ok "pushed $BRANCH"

if [[ "$OPEN_PR" == "1" ]]; then
  if command -v gh >/dev/null 2>&1; then
    log "Opening PR"
    gh pr create --fill --head "$BRANCH" || warn "gh pr create failed (open manually)"
  else
    warn "gh not available — open the PR manually"
  fi
fi
