#!/usr/bin/env bash
# Runs the reader's page scripts (Core/ReaderRenderer.swift) in WebKit, inside the
# official Playwright image so no browser dependencies are needed on the host.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
exec docker run --rm --ipc=host --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$root:$root" -w "$root/Tests/ReaderJS" \
  -e RENDERER="$root/Core/ReaderRenderer.swift" \
  mcr.microsoft.com/playwright:v1.63.0-noble node reader.spec.mjs
