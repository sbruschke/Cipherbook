#!/usr/bin/env bash
# Runs the JournalCore tests on Linux in the official Swift image. The repo is mounted at its
# own path because the sync tests read testdata/ relative to #filePath.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$root:$root" -w "$root/Packages/JournalCore" \
  swift:6.3.3-noble swift test "$@"
