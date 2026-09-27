#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/java}"
[[ -x "${JAVA:-}" ]] || JAVA="/opt/homebrew/opt/openjdk@21/bin/java"
[[ -x "$JAVA" ]] || JAVA="$(command -v java || true)"
[[ -x "$JAVA" ]] || { echo "Java not found" >&2; exit 1; }
if [[ ! -f metabase.jar ]]; then echo "metabase.jar missing" >&2; exit 1; fi
if curl -sf -o /dev/null --max-time 2 http://localhost:3000/api/health; then
  echo "Metabase already up at http://localhost:3000"; exit 0
fi
export MB_LOAD_SAMPLE_CONTENT=false MB_ANON_TRACKING_ENABLED=false
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Xmx512m -Xms128m}"
nohup "$JAVA" -jar metabase.jar > metabase.log 2>&1 &
echo $! > metabase.pid
echo "Started PID $(cat metabase.pid)"
for i in $(seq 1 60); do
  if curl -sf -o /dev/null --max-time 2 http://localhost:3000/api/health; then
    echo "Ready http://localhost:3000"; exit 0
  fi
  kill -0 "$(cat metabase.pid)" 2>/dev/null || { echo "died — see metabase.log (often RAM)"; exit 1; }
  sleep 5
done
echo "Still starting — check metabase.log"; exit 1
