#!/usr/bin/env bash
# Shared helpers for LaunchPilot. Sourced by the step scripts; not run directly.
set -euo pipefail

LP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS_DIR="$LP_DIR/jobs"

# Workspace root: product repos live here (apps, marketing sites).
# Override with PILOT_WORKSPACE (shell or pilot.env). Default: parent of LaunchPilot.
# Built-in kits live under LaunchPilot/kits/ (testflight, appstore) — not in the workspace.
_set_workspace() {
  DESKTOP="${PILOT_WORKSPACE:-$(cd "$LP_DIR/.." && pwd)}"
}
_set_workspace

TF_KIT="$LP_DIR/kits/testflight"
ASC_KIT="$LP_DIR/kits/appstore"

# Prefer Apple-silicon Homebrew + system universal binaries over /usr/local Intel tools.
# Rosetta is deprecated after macOS 27 — see scripts/check-native-tools.sh.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# --- logging --------------------------------------------------------------
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

# --- config ---------------------------------------------------------------
load_env() {
  if [[ -f "$LP_DIR/config/pilot.env" ]]; then
    # shellcheck disable=SC1091
    source "$LP_DIR/config/pilot.env"
  fi
  _set_workspace
}

# Resolve a product into P_* shell vars (P_NAME, P_TYPE, P_REPO, ...).
# Also sets REPO_DIR to the absolute repo path.
#
# repo resolution:
#   absolute path          → as-is
#   examples/... or ./...  → under LaunchPilot (bundled demos)
#   otherwise              → $PILOT_WORKSPACE/<repo> (sibling product repos)
resolve_product() {
  local product="${1:?usage: resolve_product <product>}"
  local assigns
  assigns="$(node "$LP_DIR/scripts/_product.mjs" "$product")" || return 1
  eval "$assigns"
  if [[ "$P_REPO" = /* ]]; then
    REPO_DIR="$P_REPO"
  elif [[ "$P_REPO" == examples/* || "$P_REPO" == ./* ]]; then
    REPO_DIR="$LP_DIR/${P_REPO#./}"
  else
    REPO_DIR="$DESKTOP/$P_REPO"
  fi
  if [[ ! -d "$REPO_DIR" ]]; then
    err "repo not found: $REPO_DIR"
    return 1
  fi
}

list_products() { node "$LP_DIR/scripts/_product.mjs"; }

# --- job scaffolding ------------------------------------------------------
new_job_dir() {
  local product="$1"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local dir
  # The timestamp is useful to humans, but is not unique when two runs start
  # in the same second. Keep evidence from concurrent/rapid runs separate.
  dir="$(mktemp -d "$JOBS_DIR/${product}-${stamp}-XXXXXX")"
  printf '%s' "$dir"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; return 1; }
}

# --- notifications ---------------------------------------------------------
notify_pipeline() {
  local title="$1"
  local message="$2"
  local job_dir="${3:-}"
  bash "$LP_DIR/scripts/notify.sh" "$message" "$job_dir" "$title" || true
}

# --- full pipeline --------------------------------------------------------
# run_pipeline <product> "<prompt>" [--ship-preview] [--ship-prod]
#              [--ship-testflight] [--ship-appstore] [--ship]
# Default: code -> build -> qa -> commit -> push -> PR, then stop.
# Opt-in ship flags continue past the gate. Off unless you pass a flag.
# --ship never implies App Store submit; that requires --ship-appstore alone.
run_pipeline() {
  local product="${1:?usage: run <product> \"<prompt>\" [--ship-…]}"
  shift
  local prompt=""
  local ship_preview=0 ship_prod=0 ship_testflight=0 ship_appstore=0 ship_auto=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ship-preview) ship_preview=1; shift ;;
      --ship-prod) ship_prod=1; shift ;;
      --ship-testflight) ship_testflight=1; shift ;;
      --ship-appstore) ship_appstore=1; shift ;;
      --ship) ship_auto=1; shift ;;
      --*)
        err "unknown run flag: $1"
        err "  allowed: --ship-preview --ship-prod --ship-testflight --ship-appstore --ship"
        return 1
        ;;
      *)
        if [[ -z "$prompt" ]]; then
          prompt="$1"
          shift
        else
          err "unexpected argument: $1"
          return 1
        fi
        ;;
    esac
  done

  : "${prompt:?provide a prompt}"
  load_env
  resolve_product "$product"

  if [[ "$ship_auto" == "1" ]]; then
    if [[ "$P_TYPE" == "web" ]]; then
      ship_prod=1
    else
      ship_testflight=1
    fi
    # Intentionally never sets ship_appstore — ASC Submit is a separate opt-in.
  fi

  # Optional per-product hint from products.json (P_AUTO_SHIP). Still requires a
  # CLI ship flag — this only warns if config says auto but no flag was passed.
  if [[ -n "${P_AUTO_SHIP:-}" && "${P_AUTO_SHIP}" != "0" && "${P_AUTO_SHIP}" != "false" ]]; then
    if [[ "$ship_preview$ship_prod$ship_testflight$ship_appstore" == "0000" ]]; then
      warn "products.json auto_ship=$P_AUTO_SHIP but no --ship* flag — not shipping (pass a flag to opt in)"
    fi
  fi

  local job_dir
  job_dir="$(new_job_dir "$product")"
  log "Pipeline: $P_NAME  (job: $job_dir)"
  printf '%s\n' "$prompt" > "$job_dir/prompt.txt"
  {
    echo "ship_preview=$ship_preview"
    echo "ship_prod=$ship_prod"
    echo "ship_testflight=$ship_testflight"
    echo "ship_appstore=$ship_appstore"
  } > "$job_dir/ship-flags.txt"

  notify_pipeline "LaunchPilot started" "$P_NAME: $prompt" "$job_dir"

  local pipeline_rc=0
  set +e
  bash "$LP_DIR/scripts/code.sh" "$product" "$prompt" "$job_dir" 2>&1 | tee -a "$job_dir/log.txt"
  pipeline_rc=${PIPESTATUS[0]}
  set -e
  if [[ "$pipeline_rc" -ne 0 ]]; then
    notify_pipeline "LaunchPilot failed (code)" "$P_NAME: agent/code step exited $pipeline_rc" "$job_dir"
    return "$pipeline_rc"
  fi

  local build_rc=0
  if ! bash "$LP_DIR/scripts/build.sh" "$product" 2>&1 | tee -a "$job_dir/log.txt"; then
    build_rc=1
    warn "Build failed — retrying once after 3s"
    sleep 3
    if ! bash "$LP_DIR/scripts/build.sh" "$product" 2>&1 | tee -a "$job_dir/log.txt"; then
      notify_pipeline "LaunchPilot failed (build)" "$P_NAME: build failed twice — see $job_dir" "$job_dir"
      return 1
    fi
  fi

  if ! bash "$LP_DIR/scripts/qa.sh" "$product" "$job_dir" 2>&1 | tee -a "$job_dir/log.txt"; then
    err "Required QA failed — stopping pipeline before release"
    notify_pipeline "LaunchPilot failed (QA)" "$P_NAME: required QA failure — see $job_dir" "$job_dir"
    return 1
  fi

  local msg="pilot: $prompt"
  if ! bash "$LP_DIR/scripts/release.sh" "$product" "$msg" --pr "$job_dir" 2>&1 | tee -a "$job_dir/log.txt"; then
    notify_pipeline "LaunchPilot failed (release)" "$P_NAME: release/PR step failed — see $job_dir" "$job_dir"
    return 1
  fi

  ok "Auto steps done: code, build, qa, commit, push, PR (see $job_dir)"

  local did_ship=0
  run_ship_step() {
    local phase="$1"
    shift
    local rc=0
    if "$@" 2>&1 | tee -a "$job_dir/log.txt"; then
      return 0
    else
      rc="${PIPESTATUS[0]}"
      notify_pipeline "LaunchPilot failed (ship)" "$P_NAME: $phase step exited $rc — see $job_dir" "$job_dir"
      return "$rc"
    fi
  }

  if [[ "$P_TYPE" == "web" ]]; then
    if [[ "$ship_preview" == "1" ]]; then
      log "Auto-ship: web preview deploy"
      run_ship_step "web preview deploy" bash "$LP_DIR/scripts/deploy-web.sh" "$product"
      did_ship=1
    fi
    if [[ "$ship_prod" == "1" ]]; then
      log "Auto-ship: PRODUCTION web deploy (explicit --ship-prod / --ship)"
      run_ship_step "web production deploy" bash "$LP_DIR/scripts/deploy-web.sh" "$product" --prod
      did_ship=1
    fi
    if [[ "$ship_appstore" == "1" ]]; then
      warn "--ship-appstore ignored for web products"
    fi
  else
    if [[ "$ship_preview" == "1" ]]; then
      warn "--ship-preview ignored for apps (no preview deploy path)"
    fi
    if [[ "$ship_prod" == "1" ]]; then
      warn "--ship-prod ignored for apps — use --ship-testflight or --ship"
    fi
    if [[ "$ship_testflight" == "1" ]]; then
      log "Auto-ship: TestFlight upload (explicit --ship-testflight / --ship)"
      run_ship_step "TestFlight upload" bash "$LP_DIR/scripts/testflight.sh" "$product" --confirm
      did_ship=1
    fi
    if [[ "$ship_appstore" == "1" ]]; then
      log "Auto-ship: App Store Submit for Review (explicit --ship-appstore ONLY — not covered by --ship)"
      run_ship_step "App Store submit" bash "$LP_DIR/scripts/appstore-submit.sh" "$product" --confirm
      did_ship=1
    fi
  fi

  if [[ "$did_ship" == "0" ]]; then
    log "Pipeline reached the approval gate (no --ship* flags)"
    notify_pipeline "LaunchPilot PR ready" "$P_NAME: PR ready — review/merge then ship. Job: $job_dir" "$job_dir"
    if [[ "$P_TYPE" == "web" ]]; then
      echo "  Next: ./bin/pilot deploy $product            # preview"
      echo "     or: ./bin/pilot deploy $product --prod    # production"
      echo "     or: ./bin/pilot run $product \"…\" --ship-prod"
    else
      echo "  Next: ./bin/pilot testflight $product --confirm"
      echo "     or: ./bin/pilot run $product \"…\" --ship-testflight"
      echo "  Optional later: ./bin/pilot appstore-submit $product --dry-run"
      echo "               or: ./bin/pilot run $product \"…\" --ship-appstore"
    fi
  else
    ok "Ship step finished for $P_NAME"
    notify_pipeline "LaunchPilot shipped" "$P_NAME: ship step finished. Job: $job_dir" "$job_dir"
    if [[ "$P_TYPE" == "app" && "$ship_appstore" != "1" ]]; then
      echo "  App Store Submit still opt-in: ./bin/pilot appstore-submit $product --dry-run"
    fi
  fi
}
