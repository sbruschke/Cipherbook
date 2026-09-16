#!/usr/bin/env bash
# Runs the KeyboardCore tests on Linux in the official Swift image. The repo is
# mounted at its own path because the tests find lexicon.dat relative to #filePath.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$root:$root" -w "$root/Packages/KeyboardCore" \
  swift:6.3.3-noble swift test "$@"
