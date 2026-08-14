#!/usr/bin/env bash
# Make the Linux runtime tree self-contained:
#   1. copy the explicitly listed non-system libraries (config/
#      bundled-libs.linux) from the build host into runtime/lib;
#   2. set RUNPATH on every ELF so private dependencies resolve through
#      $ORIGIN-relative paths only.
# Nothing is bundled implicitly — an unexpected new dependency is caught by
# verify-runtime-links-linux.sh and blocks the build.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need patchelf "e.g. apt-get install patchelf"
need ldd

[[ -d "${RUNTIME_DIR}/bin" ]] || die "runtime tree not found (run scripts/prune-stage.sh)"

# Map dependency SONAME -> resolved path, taken from the freshly built
# binaries themselves so we copy exactly what they link against.
declare -A dep_path
while IFS= read -r line; do
  name="$(awk '{print $1}' <<<"${line}")"
  path="$(awk '{print $3}' <<<"${line}")"
  [[ -n "${name}" && -n "${path}" && "${path}" == /* ]] || continue
  dep_path["${name}"]="${path}"
done < <(
  for f in "${RUNTIME_DIR}"/bin/*; do
    is_elf "${f}" && ldd "${f}" 2>/dev/null || true
  done | grep ' => /' || true
)

while IFS= read -r soname; do
  src="${dep_path[${soname}]:-}"
  [[ -n "${src}" ]] || die "bundled library ${soname} is not a dependency of any runtime binary; update config/bundled-libs.linux"
  cp -L "${src}" "${RUNTIME_DIR}/lib/${soname}"
  chmod 0755 "${RUNTIME_DIR}/lib/${soname}"
  log "bundled ${soname} (from ${src})"
done < <(read_options_file "${REPO_ROOT}/config/bundled-libs.linux")

for f in "${RUNTIME_DIR}"/bin/*; do
  is_elf "${f}" || continue
  # shellcheck disable=SC2016  # literal $ORIGIN is expanded by the loader
  patchelf --set-rpath '$ORIGIN/../lib' "${f}"
done

while IFS= read -r f; do
  is_elf "${f}" || continue
  # shellcheck disable=SC2016  # literal $ORIGIN is expanded by the loader
  patchelf --set-rpath '$ORIGIN' "${f}"
done < <(find "${RUNTIME_DIR}/lib" -type f -name '*.so*')

log "RUNPATH rewritten to \$ORIGIN-relative paths"
