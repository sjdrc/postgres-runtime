#!/usr/bin/env bash
# Release-blocking relocation test (plan §10). Extracts the packaged
# archive to an arbitrary path, runs the full smoke suite, then MOVES the
# runtime tree to a completely different path and restarts the SAME
# cluster with the moved binaries, re-running the essential checks.
#
#   relocation-test.sh [--archive FILE] [--keep]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need zstd
need tar

archive="${OUT_DIR}/$(artifact_name).tar.zst"
keep=no
while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) archive="$2"; shift 2 ;;
    --keep) keep=yes; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ -f "${archive}" ]] || die "archive not found: ${archive} (run scripts/package.sh)"

base="$(mktemp -d "${TMPDIR:-/tmp}/pg-runtime-reloc.XXXXXX")"
cleanup() { [[ "${keep}" == yes ]] || rm -rf "${base}"; }
trap cleanup EXIT

path_a="${base}/runtime-test-A/some/nested/dir"
path_b="${base}/runtime-test-B/completely-different-name"
state="${base}/state"
mkdir -p "${path_a}" "${path_b}" "${state}"

log "extracting $(basename "${archive}") to ${path_a}"
zstd -dc "${archive}" | tar -xf - -C "${path_a}"
[[ -d "${path_a}/postgres-runtime" ]] || die "archive does not contain a postgres-runtime/ top-level directory"

log "phase 1: full smoke suite at path A"
"${SCRIPT_DIR}/smoke-test.sh" --runtime "${path_a}/postgres-runtime" \
  --workdir "${state}" --phase full

log "moving runtime tree: path A -> path B"
mv "${path_a}/postgres-runtime" "${path_b}/pg"

log "phase 2: essential checks with the moved runtime against the same cluster"
"${SCRIPT_DIR}/smoke-test.sh" --runtime "${path_b}/pg" \
  --workdir "${state}" --phase essential

log "relocation test passed"
if [[ "${keep}" == yes ]]; then
  log "kept test state at ${base}"
fi
