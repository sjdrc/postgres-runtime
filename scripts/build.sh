#!/usr/bin/env bash
# Build the PostgreSQL server, client tools, and all supplied contrib
# modules (world-bin = everything except documentation).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need make

[[ -f "${BUILD_DIR}/GNUmakefile" ]] || die "build tree not configured (run scripts/configure.sh)"

jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

# PostgreSQL's makefiles guard their generated-headers ordering with
# MAKELEVEL=0, assuming they are the top-level make. When invoked beneath
# this repo's Makefile that guard is defeated and parallel builds race on
# headers like utils/errcodes.h. Scrub the inherited make environment so
# the upstream build behaves like a fresh top-level invocation, and build
# the generated headers explicitly first (the direct target is unguarded).
pg_make() { env -u MAKELEVEL -u MAKEFLAGS -u MFLAGS make "$@"; }

log "generating headers"
pg_make -C "${BUILD_DIR}/src/backend" generated-headers >/dev/null

log "building world-bin with -j${jobs}"
pg_make -C "${BUILD_DIR}" -j"${jobs}" world-bin
log "build complete"
