#!/usr/bin/env bash
# Print the versions.yaml platform list as a compact JSON array, for use
# as a CI build matrix.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"
need jq
ver_list platforms | jq -Rn '[inputs]' -c
