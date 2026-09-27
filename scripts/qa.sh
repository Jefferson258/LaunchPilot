#!/usr/bin/env bash
# Capture visual-QA screenshots for a product, if a QA command is configured.
# Optional 2nd arg: a job dir to copy screenshots into as evidence.
#
# Enforces products.json depth fields:
#   qa_min_pngs, qa_required (comma-separated)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
PRODUCT_KEY="${1:?usage: qa.sh <product> [job_dir]}"
resolve_product "$PRODUCT_KEY"
JOB_DIR="${2:-}"

if [[ "${P_QA_STRICT:-true}" == "false" || "${P_QA_STRICT:-}" == "0" ]]; then
  warn "qa_strict=false in products.json is ignored — required QA still fails closed"
fi

if [[ -z "${P_QA_CMD:-}" ]]; then
  err "$P_NAME has no QA command configured — required QA cannot run"
  err "  (add qa_cmd in config/products.json; see kits/qa/README.md)"
  exit 1
fi

cd "$REPO_DIR"
log "Running visual QA for $P_NAME: $P_QA_CMD"
export QA_DEPTH="${QA_DEPTH:-deep}"
eval "$P_QA_CMD"

OUT_DIR="$REPO_DIR/${P_QA_OUT:-qa-screenshots}"
if [[ ! -d "$OUT_DIR" ]]; then
  err "expected screenshot dir not found: $OUT_DIR"
  exit 1
fi

count="$(find "$OUT_DIR" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
ok "$P_NAME QA: $count screenshot(s) in $OUT_DIR"

MANIFEST="$OUT_DIR/qa-manifest.json"
python3 - "$OUT_DIR" "$P_NAME" "$PRODUCT_KEY" "$REPO_DIR" "$QA_DEPTH" "$count" <<'PY'
import json, sys, pathlib, datetime
out, name, key, repo, depth, count = sys.argv[1:7]
files = sorted(p.name for p in pathlib.Path(out).glob("*.png"))
manifest = {
    "product": name,
    "product_key": key,
    "repo": repo,
    "out": out,
    "qa_depth": depth,
    "count": int(count),
    "files": files,
    "captured_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
path = pathlib.Path(out) / "qa-manifest.json"
path.write_text(json.dumps(manifest, indent=2) + "\n")
print(path)
PY
ok "wrote $MANIFEST"

fail=0
if [[ -n "${P_QA_MIN_PNGS:-}" ]]; then
  if [[ "$count" -lt "$P_QA_MIN_PNGS" ]]; then
    err "QA depth check failed: got $count PNGs, need >= $P_QA_MIN_PNGS"
    fail=1
  else
    ok "qa_min_pngs satisfied ($count >= $P_QA_MIN_PNGS)"
  fi
fi

if [[ -n "${P_QA_REQUIRED:-}" ]]; then
  OLD_IFS="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  set -- $P_QA_REQUIRED
  IFS="$OLD_IFS"
  for r in "$@"; do
    r="$(echo "$r" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$r" ]] && continue
    if [[ ! -f "$OUT_DIR/$r" ]]; then
      err "missing required QA screenshot: $r"
      fail=1
    fi
  done
  if [[ "$fail" == "0" ]]; then
    ok "qa_required filenames present"
  fi
fi

if [[ -n "$JOB_DIR" ]]; then
  mkdir -p "$JOB_DIR/screenshots"
  cp "$OUT_DIR"/*.png "$JOB_DIR/screenshots/" 2>/dev/null || true
  cp "$MANIFEST" "$JOB_DIR/screenshots/" 2>/dev/null || true
  ok "copied screenshots + manifest into job evidence"
fi

if [[ "$fail" != "0" ]]; then
  exit 1
fi
