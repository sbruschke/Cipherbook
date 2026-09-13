#!/usr/bin/env bash
# Pull the IPA the LiveContainer source feed is currently serving into
# ./build/Cipherbook.ipa for local testing — i.e. exactly what the phone gets.
#
# This script does NOT push the IPA to the iPhone — that step happens through
# the iphone MCP bridge (a Claude action), because the bridge listens on the
# local LAN and is not reachable from a CI runner.
#
# Usage: ./scripts/fetch-latest-ipa.sh [--artifact]
#   --artifact  take the newest build-ipa workflow artifact instead of the feed,
#               for checking a branch build that was never released.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
DEST_DIR="$REPO_ROOT/build"
DEST="$DEST_DIR/Cipherbook.ipa"
mkdir -p "$DEST_DIR"
rm -f "$DEST"

if [[ "${1:-}" == "--artifact" ]]; then
  LATEST_RUN_ID="$(gh run list --workflow=build-ipa --status=success --limit=1 \
    --json databaseId --jq '.[0].databaseId')"
  [[ -n "$LATEST_RUN_ID" ]] || { echo "no successful build-ipa run found" >&2; exit 1; }
  echo "downloading artifact from run $LATEST_RUN_ID..."
  gh run download "$LATEST_RUN_ID" --name Cipherbook-ipa --dir "$DEST_DIR"
else
  FEED="https://raw.githubusercontent.com/sbruschke/Cipherbook/main/source.json"
  META="$(curl -fsSL "$FEED")"
  URL="$(jq -r '.apps[0].downloadURL' <<<"$META")"
  echo "feed: $(jq -r '.apps[0].version + " (build " + .apps[0].buildVersion + ", " + .apps[0].versionDate + ")"' <<<"$META")"
  curl -fsSL "$URL" -o "$DEST"
fi

[[ -f "$DEST" ]] || { echo "Cipherbook.ipa not found" >&2; exit 1; }
echo "fetched: $DEST ($(stat -c%s "$DEST") bytes)"
echo "next step: ask Claude to push it to the iPhone via iphone_upload_binary"
