#!/usr/bin/env bash
# Create a GitHub Release with notes since the previous tag, and prepend CHANGELOG.md.
# Usage:
#   publish.sh --repo DIR --tag TAG [--title TITLE] [--dry-run] [--commit] [--allow-existing]
# --commit writes CHANGELOG.md on the current branch (that file only) and pushes
# the branch + tag. Does not force-push. Refuses tags that already have a GitHub
# Release unless --allow-existing.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:${PATH:-/usr/bin}"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="."
TAG=""
TITLE=""
DRY=0
ALLOW_EXISTING=0
COMMIT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --allow-existing) ALLOW_EXISTING=1; shift ;;
    --commit) COMMIT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$TAG" ]] || { echo "usage: publish.sh --repo DIR --tag TAG" >&2; exit 1; }
TITLE="${TITLE:-$TAG}"
REPO="$(cd "$REPO" && pwd)"
cd "$REPO"
NOTES="$(mktemp)"
BLOCK="$(mktemp)"
trap 'rm -f "$NOTES" "$BLOCK"' EXIT
"$KIT/generate.sh" --repo "$REPO" --out "$NOTES"

CHANGELOG="$REPO/CHANGELOG.md"
{
  echo "## $TITLE — $(date -u +%Y-%m-%d)"
  echo
  cat "$NOTES"
  echo
} > "$BLOCK"
if [[ -f "$CHANGELOG" ]]; then
  cat "$CHANGELOG" >> "$BLOCK"
else
  {
    echo "# Changelog"
    echo
    echo "All notable releases for this repo. Generated/updated by LaunchPilot \`kits/release-notes\` on each TestFlight or production web ship. Prefer GitHub **Releases** as the canonical view."
    echo
  } >> "$BLOCK"
fi
if [[ "$DRY" == "1" ]]; then
  echo "[dry-run] would write CHANGELOG.md and gh release create $TAG"
  head -40 "$BLOCK"
  exit 0
fi
mv "$BLOCK" "$CHANGELOG"
BLOCK=""

if [[ "$COMMIT" == "1" ]]; then
  git add -- CHANGELOG.md
  if git diff --cached --quiet -- CHANGELOG.md; then
    echo "CHANGELOG.md unchanged — skipping commit"
  else
    git commit -m "$(cat <<EOF
Record changelog for ${TITLE}.

EOF
)"
  fi
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh not available — CHANGELOG.md updated; create the GitHub Release manually" >&2
  exit 0
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  if [[ "$ALLOW_EXISTING" == "1" ]]; then
    echo "release $TAG already exists — skipping create"
    exit 0
  fi
  echo "release $TAG already exists" >&2
  exit 1
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "$TITLE"
fi
if [[ "$COMMIT" == "1" ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$BRANCH"
fi
git push origin "$TAG"
gh release create "$TAG" --title "$TITLE" --notes-file "$NOTES"
echo "published https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
