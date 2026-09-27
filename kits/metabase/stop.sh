#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$DIR/metabase.pid" ]]; then
  kill "$(cat "$DIR/metabase.pid")" 2>/dev/null || true
  rm -f "$DIR/metabase.pid"
fi
pkill -f 'metabase.jar' 2>/dev/null || true
echo "stopped"
