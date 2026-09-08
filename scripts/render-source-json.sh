#!/usr/bin/env bash
# Render the AltStore/SideStore/LiveContainer-format source.json for Cipherbook.
#
# Usage: render-source-json.sh <version> <build> <iso-date> <description> <ipa-path>
# Writes JSON to stdout; escaping is delegated to jq.

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <version> <build> <iso-date> <description> <ipa-path>" >&2
  exit 2
fi

VERSION="$1"; BUILD="$2"; DATE="$3"; DESCRIPTION="$4"; IPA_PATH="$5"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "error: IPA not found at $IPA_PATH" >&2
  exit 1
fi

file_size() {
  if size=$(stat -c%s "$1" 2>/dev/null); then echo "$size"; else stat -f%z "$1"; fi
}

SIZE=$(file_size "$IPA_PATH")
BASE="https://raw.githubusercontent.com/sbruschke/Cipherbook/main"

jq -n \
  --arg version "$VERSION" \
  --arg build "$BUILD" \
  --arg date "$DATE" \
  --arg desc "$DESCRIPTION" \
  --arg url "${BASE}/releases/Cipherbook-${VERSION}-build${BUILD}.ipa" \
  --arg source "${BASE}/source.json" \
  --argjson size "$SIZE" \
  '{
    name: "Cipherbook",
    identifier: "dev.dxshdw.cipherbook.source",
    sourceURL: $source,
    apps: [{
      name: "Cipherbook",
      bundleIdentifier: "dev.dxshdw.cipherbook",
      developerName: "dxshdw",
      subtitle: "Dual-font EPUB reader",
      localizedDescription: "An EPUB reader that renders every word in two typefaces at once — a main font on the line and a smaller second font directly underneath — for learning a cipher or conscript. Import your own fonts, switch them in two taps, and build custom colour themes.",
      tintColor: "#7FB28A",
      version: $version,
      buildVersion: $build,
      versionDate: $date,
      versionDescription: $desc,
      downloadURL: $url,
      size: $size,
      screenshotURLs: [],
      permissions: []
    }],
    news: []
  }'
