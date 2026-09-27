#!/usr/bin/env bash
# Check an HTTP deployment without sending credentials or mutating state.
#   http-smoke.sh <base-url> [route ...]
set -euo pipefail

ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
usage() { printf 'usage: http-smoke.sh <base-url> [route ...]\n'; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
BASE_URL="${1:?usage: http-smoke.sh <base-url> [route ...]}"
shift

if [[ ! "$BASE_URL" =~ ^https?:// ]]; then
  printf 'error: URL must start with http:// or https://\n' >&2
  exit 2
fi

routes=("$@")
[[ "${#routes[@]}" -gt 0 ]] || routes=("/")
timeout="${PILOT_HTTP_SMOKE_TIMEOUT:-20}"
failed=0

for route in "${routes[@]}"; do
  if [[ "$route" =~ ^https?:// ]]; then
    url="$route"
  else
    [[ "$route" == /* ]] || route="/$route"
    url="${BASE_URL%/}$route"
  fi

  if ! status="$(curl --fail --location --silent --show-error \
    --max-time "$timeout" --output /dev/null --write-out '%{http_code}' "$url")"; then
    err "HTTP smoke failed: $url"
    failed=1
    continue
  fi

  case "$status" in
    2*|3*) ok "HTTP smoke passed: $url ($status)" ;;
    *) err "HTTP smoke failed: $url ($status)"; failed=1 ;;
  esac
done

exit "$failed"
