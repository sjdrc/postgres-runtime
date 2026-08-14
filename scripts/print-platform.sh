#!/usr/bin/env bash
# Print the host platform identifier (e.g. linux-amd64). CI uses this to
# assert that a job builds natively for its declared target — a platform
# must never be published from a cross-compiled, untested build.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"
host_platform
