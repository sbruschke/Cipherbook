#!/usr/bin/env bash
# Pull the most recent successful Cipherbook build artifact from GitHub Actions
# into ./build/Cipherbook.ipa for local testing.
#
# Requires `gh` CLI authenticated against the repo origin.
#
# This script does NOT push the IPA to the iPhone — that step happens through
# the iphone MCP bridge (a Claude action), because the bridge listens on the
# local LAN and is not reachable from a CI runner.
#
# Usage: ./scripts/fetch-latest-ipa.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
DEST_DIR="$REPO_ROOT/build"

mkdir -p "$DEST_DIR"
rm -f "$DEST_DIR/Cipherbook.ipa"

LATEST_RUN_ID="$(gh run list \
  --workflow=build-ipa \
  --status=success \
  --limit=1 \
  --json databaseId \
  --jq '.[0].databaseId')"

if [[ -z "$LATEST_RUN_ID" ]]; then
  echo "no successful build-ipa run found" >&2
  exit 1
fi

echo "downloading artifact from run $LATEST_RUN_ID..."
gh run download "$LATEST_RUN_ID" --name Cipherbook-ipa --dir "$DEST_DIR"

if [[ ! -f "$DEST_DIR/Cipherbook.ipa" ]]; then
  echo "Cipherbook.ipa not found in artifact" >&2
  exit 1
fi

SIZE="$(stat -c%s "$DEST_DIR/Cipherbook.ipa")"
echo "fetched: $DEST_DIR/Cipherbook.ipa ($SIZE bytes)"
echo "next step: ask Claude to push it to the iPhone via iphone_upload_binary"
