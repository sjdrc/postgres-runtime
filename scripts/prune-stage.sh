#!/usr/bin/env bash
# Copy the staged install into the runtime tree and prune development-only
# content. Pruning is deliberately conservative: only clearly non-runtime
# material is removed, and the result is validated by the smoke and
# relocation tests, never by guesswork.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

staged="${STAGE_DIR}${PG_PREFIX}"
[[ -d "${staged}" ]] || die "staged install not found (run scripts/install-stage.sh)"

rm -rf "${RUNTIME_PARENT}"
mkdir -p "${RUNTIME_DIR}"
(cd "${staged}" && tar -cf - .) | (cd "${RUNTIME_DIR}" && tar -xf -)

# bin: keep exactly the tools the runtime ships.
for f in "${RUNTIME_DIR}"/bin/*; do
  base="$(basename "${f}")"
  keep=no
  for t in "${RUNTIME_TOOLS[@]}"; do
    [[ "${base}" == "${t}" ]] && keep=yes
  done
  [[ "${keep}" == yes ]] || rm -f "${f}"
done

# Development material: headers, pkg-config, PGXS build infrastructure,
# static libraries, ECPG client libraries, and bare .so linker symlinks.
rm -rf "${RUNTIME_DIR}/include"
rm -rf "${RUNTIME_DIR}/lib/pkgconfig" "${RUNTIME_DIR}/lib/pgxs"
find "${RUNTIME_DIR}/lib" -name '*.a' -type f -delete
rm -f "${RUNTIME_DIR}"/lib/libecpg* "${RUNTIME_DIR}"/lib/libpgtypes*
find "${RUNTIME_DIR}/lib" -maxdepth 1 -type l -name '*.so' -delete
find "${RUNTIME_DIR}/lib" -maxdepth 1 -type l -name '*.dylib' ! -name '*.[0-9]*' -delete 2>/dev/null || true

# Documentation trees, if any were installed.
rm -rf "${RUNTIME_DIR}/share/doc" "${RUNTIME_DIR}/share/man"

# --- Release-blocking content checks (plan §23) ---
for t in "${RUNTIME_TOOLS[@]}"; do
  [[ -x "${RUNTIME_DIR}/bin/${t}" ]] || die "required binary missing after prune: bin/${t}"
done
for ext in $(ver_list extensions.required) $(ver_list extensions.optional); do
  [[ -f "${RUNTIME_DIR}/share/extension/${ext}.control" ]] \
    || die "required extension control file missing: share/extension/${ext}.control"
  if ! ls "${RUNTIME_DIR}/lib/${ext}".* >/dev/null 2>&1; then
    die "required extension module missing: lib/${ext}.*"
  fi
done
for f in postgres.bki system_views.sql information_schema.sql; do
  [[ -f "${RUNTIME_DIR}/share/${f}" ]] || die "required share file missing: share/${f}"
done
for d in timezone timezonesets tsearch_data extension; do
  [[ -d "${RUNTIME_DIR}/share/${d}" ]] || die "required share directory missing: share/${d}"
done

log "runtime tree ready at ${RUNTIME_DIR}"
du -sh "${RUNTIME_DIR}" >&2
