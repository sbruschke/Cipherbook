#!/usr/bin/env bash
# Print the marketing version from project.yml, the single source of truth.
#
# Usage: ./scripts/version.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
sed -n 's/^ *MARKETING_VERSION: *"\([0-9.]*\)".*/\1/p' project.yml | head -1
