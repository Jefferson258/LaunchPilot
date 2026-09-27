#!/usr/bin/env bash
# Deploy a marketing site to Vercel. Preview by default; --prod is gated.
#   deploy-web.sh <product> [--prod]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
resolve_product "${1:?usage: deploy-web.sh <product> [--prod]}"
PROD=0
[[ "${2:-}" == "--prod" ]] && PROD=1

if [[ "$P_TYPE" != "web" ]]; then
  err "$P_NAME is not a web product"
  exit 1
fi
require_cmd vercel
if [[ -z "${VERCEL_TOKEN:-}" ]]; then
  err "VERCEL_TOKEN not set — add it to config/pilot.env (https://vercel.com/account/tokens)"
  exit 1
fi

SCOPE_ARGS=()
[[ -n "${VERCEL_SCOPE:-}" ]] && SCOPE_ARGS=(--scope "$VERCEL_SCOPE")

cd "$REPO_DIR"
# Ensure .vercel/project.json exists (non-interactive deploys need link + scope).
if [[ ! -f .vercel/project.json ]] && [[ -n "${P_VERCEL_PROJECT:-}" ]]; then
  if ! vercel link --yes --project "$P_VERCEL_PROJECT" "${SCOPE_ARGS[@]}" --token="$VERCEL_TOKEN"; then
    err "could not link $P_NAME to Vercel project $P_VERCEL_PROJECT"
    exit 1
  fi
fi

DEPLOY_URL=""
PREVIOUS_PROD_URL=""
PREVIOUS_DEPLOY_ID=""

fetch_previous_production() {
  PREVIOUS_PROD_URL=""
  PREVIOUS_DEPLOY_ID=""
  local pj="$REPO_DIR/.vercel/project.json"
  if [[ -z "${VERCEL_TOKEN:-}" || ! -f "$pj" ]]; then
    warn "no previous production URL (missing .vercel/project.json or VERCEL_TOKEN)"
    return 0
  fi
  local out
  if ! out="$(
    PJ="$pj" python3 - <<'PY'
import json, os, urllib.error, urllib.request
pj = json.load(open(os.environ["PJ"], encoding="utf-8"))
project_id = pj.get("projectId") or ""
org = pj.get("orgId") or ""
if not project_id:
    raise SystemExit(0)
qs = f"projectId={project_id}&target=production&limit=1"
if org:
    qs += f"&teamId={org}"
req = urllib.request.Request(
    f"https://api.vercel.com/v6/deployments?{qs}",
    headers={"Authorization": f"Bearer {os.environ['VERCEL_TOKEN']}"},
)
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.load(resp)
except urllib.error.HTTPError as exc:
    raise SystemExit(0) from exc
deps = data.get("deployments") or []
if not deps:
    raise SystemExit(0)
d = deps[0]
uid = d.get("uid") or d.get("id") or ""
url = d.get("url") or ""
if url and not url.startswith("http"):
    url = "https://" + url
print(url)
print(uid)
PY
  )"; then
    warn "could not look up previous production deployment"
    return 0
  fi
  PREVIOUS_PROD_URL="$(printf '%s\n' "$out" | sed -n '1p')"
  PREVIOUS_DEPLOY_ID="$(printf '%s\n' "$out" | sed -n '2p')"
  if [[ -n "$PREVIOUS_PROD_URL" ]]; then
    ok "previous production: $PREVIOUS_PROD_URL"
  else
    warn "no previous production deployment found (first prod ship is OK)"
  fi
}

record_web_rollback() {
  local product_key="$1"
  local dir="$LP_DIR/jobs/web-rollbacks"
  mkdir -p "$dir"
  local rec="$dir/${product_key}.json"
  REC="$rec" KEY="$product_key" PREV="$PREVIOUS_PROD_URL" PREVID="$PREVIOUS_DEPLOY_ID" NEW="$DEPLOY_URL" python3 <<'PY'
import json, os, datetime
path = os.environ["REC"]
rec = {
    "product": os.environ["KEY"],
    "previousProductionUrl": os.environ.get("PREV") or None,
    "previousDeploymentId": os.environ.get("PREVID") or None,
    "newUrl": os.environ.get("NEW") or None,
    "recordedAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "rollbackIsAutomatic": False,
}
open(path, "w", encoding="utf-8").write(json.dumps(rec, indent=2) + "\n")
print(path)
PY
  ok "recorded rollback snapshot: $rec"
}

deploy_and_capture() {
  local output
  output="$(mktemp "${TMPDIR:-/tmp}/launchpilot-deploy.XXXXXX")"
  if ! vercel "$@" 2>&1 | tee "$output"; then
    rm -f "$output"
    return 1
  fi
  DEPLOY_URL="$(awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^https:\/\/[^[:space:]]+$/) {
        url = $i
        sub(/[[:punct:]]+$/, "", url)
      }
    }
  } END { print url }' "$output")"
  rm -f "$output"
}

post_deploy_smoke() {
  [[ "${PILOT_POST_DEPLOY_SMOKE:-1}" != "0" ]] || {
    warn "post-deploy HTTP smoke check disabled (PILOT_POST_DEPLOY_SMOKE=0)"
    return 0
  }

  local smoke_url="${P_SMOKE_URL:-${PILOT_SMOKE_URL:-$DEPLOY_URL}}"
  if [[ -z "$smoke_url" ]]; then
    warn "post-deploy HTTP smoke check skipped — Vercel returned no URL"
    return 0
  fi

  log "Post-deploy HTTP smoke check: $smoke_url"
  if ! "$LP_DIR/scripts/http-smoke.sh" "$smoke_url"; then
    err "post-deploy HTTP smoke check failed"
    local rollback_target="${PREVIOUS_PROD_URL:-}"
    if [[ -z "$rollback_target" && -n "$PREVIOUS_DEPLOY_ID" ]]; then
      rollback_target="$PREVIOUS_DEPLOY_ID"
    fi
    if [[ -n "$rollback_target" ]]; then
      warn "Manual rollback to PREVIOUS production (owner approval required): vercel rollback \"$rollback_target\" --token=\"\$VERCEL_TOKEN\""
      warn "Do not rollback to the new URL ($DEPLOY_URL)."
    else
      warn "No previous production URL on file — Instant Rollback from the Vercel dashboard if needed. Rollback is never automatic."
    fi
    return 1
  fi
}

if [[ "$PROD" == "1" ]]; then
  warn "PRODUCTION deploy of $P_NAME (gated action)"
  if ! vercel pull --yes --environment=production "${SCOPE_ARGS[@]}" --token="$VERCEL_TOKEN"; then
    err "could not pull Vercel production configuration for $P_NAME"
    exit 1
  fi
  fetch_previous_production
  deploy_and_capture deploy --prod --yes "${SCOPE_ARGS[@]}" --token="$VERCEL_TOKEN"
  record_web_rollback "$1"
  ok "$P_NAME deployed to production"
  post_deploy_smoke
  RN_KIT="$LP_DIR/kits/release-notes"
  if [[ -x "$RN_KIT/publish.sh" ]]; then
    SHA="$(cd "$REPO_DIR" && git rev-parse --short HEAD)"
    TAG="${1}-web-$(date -u +%Y%m%d)-${SHA}"
    log "Publishing web release notes tag $TAG"
    "$RN_KIT/publish.sh" --repo "$REPO_DIR" --tag "$TAG" --title "$P_NAME web $(date -u +%Y-%m-%d) ($SHA)" --commit || \
      warn "release notes publish failed (deploy already succeeded)"
  fi
else
  log "Preview deploy of $P_NAME"
  if ! vercel pull --yes "${SCOPE_ARGS[@]}" --token="$VERCEL_TOKEN"; then
    err "could not pull Vercel configuration for $P_NAME"
    exit 1
  fi
  deploy_and_capture deploy --yes "${SCOPE_ARGS[@]}" --token="$VERCEL_TOKEN"
  ok "$P_NAME preview deployed"
  post_deploy_smoke
fi
