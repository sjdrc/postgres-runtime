#!/usr/bin/env bash
# Enforce the patch policy: patches/ must normally contain only README.md.
# Any actual patch requires an explanation, an upstream reference where
# applicable, a proving test, and an expiry condition — reviewed by a human,
# so its presence fails CI until the policy checklist in patches/README.md
# is explicitly satisfied and this check is amended in the same change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

extra="$(find "${REPO_ROOT}/patches" -type f ! -name 'README.md' | sort)"
if [[ -n "${extra}" ]]; then
  die "patches/ contains files beyond README.md — PostgreSQL must not be patched without following the documented policy:
${extra}"
fi
log "patch policy OK: PostgreSQL is unmodified"
