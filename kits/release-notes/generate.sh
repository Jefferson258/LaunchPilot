#!/usr/bin/env bash
# Emit release notes from git history since the previous tag.
#   generate.sh --repo DIR [--out FILE] [--since-tag TAG] [--limit N]
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:${PATH:-/usr/bin}"
REPO="."
OUT=""
SINCE=""
LIMIT=40
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --since-tag) SINCE="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
REPO="$(cd "$REPO" && pwd)"
cd "$REPO"

if [[ -z "$SINCE" ]]; then
  SINCE="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi

{
  echo "## Changes"
  echo
  if [[ -n "$SINCE" ]]; then
    echo "_Since tag \`$SINCE\`_"
    echo
    git log "${SINCE}..HEAD" --pretty=format:'- %s (%h)' --no-merges || true
  else
    echo "_First release — recent commits:_"
    echo
    git log -"$LIMIT" --pretty=format:'- %s (%h)' --no-merges || true
  fi
  echo
} | if [[ -n "$OUT" ]]; then cat >"$OUT"; else cat; fi
