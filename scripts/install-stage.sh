#!/usr/bin/env bash
# Install the built tree into a clean staging prefix under work/stage.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need make

[[ -f "${BUILD_DIR}/GNUmakefile" ]] || die "build tree not configured (run scripts/configure.sh)"

rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
log "installing world-bin into stage (DESTDIR=${STAGE_DIR})"
# Scrub inherited make environment; see the note in build.sh.
env -u MAKELEVEL -u MAKEFLAGS -u MFLAGS \
  make -C "${BUILD_DIR}" DESTDIR="${STAGE_DIR}" install-world-bin >/dev/null
[[ -x "${STAGE_DIR}${PG_PREFIX}/bin/postgres" ]] || die "staged install is missing bin/postgres"
log "staged at ${STAGE_DIR}${PG_PREFIX}"
