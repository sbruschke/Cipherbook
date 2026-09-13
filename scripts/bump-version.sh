#!/usr/bin/env bash
# Bump MARKETING_VERSION in project.yml. CI takes the build number from its own
# run number, so this is only for the human-facing part of the version.
#
# Usage: ./scripts/bump-version.sh <major|minor|patch|X.Y.Z>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[[ $# -eq 1 ]] || { echo "usage: $0 <major|minor|patch|X.Y.Z>" >&2; exit 2; }
CURRENT="$(./scripts/version.sh)"
IFS=. read -r MAJ MIN PAT <<<"$CURRENT"

case "$1" in
  major) NEXT="$((MAJ + 1)).0.0" ;;
  minor) NEXT="${MAJ}.$((MIN + 1)).0" ;;
  patch) NEXT="${MAJ}.${MIN}.$((PAT + 1))" ;;
  *)
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: '$1' is not X.Y.Z" >&2; exit 2; }
    NEXT="$1" ;;
esac

sed -i.bak "s/^\( *MARKETING_VERSION: *\)\"${CURRENT}\"/\1\"${NEXT}\"/" project.yml
rm -f project.yml.bak
echo "$CURRENT -> $NEXT"
echo "commit project.yml and push to main; CI publishes the feed."
