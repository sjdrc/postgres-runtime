#!/usr/bin/env bash
# Make the macOS runtime tree self-contained:
#   1. copy the explicitly listed non-system dylibs (config/bundled-libs.darwin,
#      typically Homebrew lz4/zstd) into runtime/lib;
#   2. give bundled dylibs @rpath install names;
#   3. rewrite every non-system reference in every Mach-O to @rpath and add
#      an @loader_path/../lib rpath;
#   4. ad-hoc re-sign everything modified (required on arm64).
# An unexpected dependency is caught by verify-runtime-links-darwin.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need otool
need install_name_tool
need codesign

[[ -d "${RUNTIME_DIR}/bin" ]] || die "runtime tree not found (run scripts/prune-stage.sh)"

is_macho() { otool -h "$1" >/dev/null 2>&1; }

# System references stay untouched; everything else is rewritten.
is_system_ref() { [[ "$1" == /usr/lib/* || "$1" == /System/Library/* ]]; }

deps_of() { otool -L "$1" | awk 'NR > 1 {print $1}'; }

# 1. Bundle listed dylibs, resolving their current paths from the freshly
#    built binaries.
declare -a bundled=()
while IFS= read -r want; do
  src=""
  for f in "${RUNTIME_DIR}"/bin/*; do
    is_macho "${f}" || continue
    while IFS= read -r dep; do
      [[ "$(basename "${dep}")" == "${want}" && "${dep}" == /* ]] && src="${dep}"
    done < <(deps_of "${f}")
  done
  [[ -n "${src}" && -f "${src}" ]] || die "bundled dylib ${want} is not a dependency of any runtime binary; update config/bundled-libs.darwin"
  cp -L "${src}" "${RUNTIME_DIR}/lib/${want}"
  chmod 0755 "${RUNTIME_DIR}/lib/${want}"
  install_name_tool -id "@rpath/${want}" "${RUNTIME_DIR}/lib/${want}"
  bundled+=("${want}")
  log "bundled ${want} (from ${src})"
done < <(read_options_file "${REPO_ROOT}/config/bundled-libs.darwin")

# 2. Rewrite references and rpaths on every Mach-O in the tree.
rewrite() {
  local f="$1" dep base
  # A dylib's own install name (LC_ID_DYLIB) is separate from what other
  # files' LC_LOAD_DYLIB references to it say, and `-change` only rewrites
  # the latter. PostgreSQL's own build sets this to the absolute --prefix
  # path (e.g. libpq.*.dylib); left alone, every dependent gets correctly
  # rewritten to @rpath/libpq.5.dylib but the library's own header still
  # advertises the absolute path, which verify-runtime-links-darwin.sh
  # (rightly) flags as a non-system absolute reference. `-bundle`-type
  # loadable modules (contrib extensions) have no LC_ID_DYLIB to set, so
  # this is harmlessly suppressed for those.
  if [[ "${f}" == "${RUNTIME_DIR}/lib/"*.dylib ]]; then
    install_name_tool -id "@rpath/$(basename "${f}")" "${f}" 2>/dev/null || true
  fi
  while IFS= read -r dep; do
    [[ "${dep}" == @rpath/* || "${dep}" == @loader_path/* ]] && continue
    is_system_ref "${dep}" && continue
    base="$(basename "${dep}")"
    install_name_tool -change "${dep}" "@rpath/${base}" "${f}"
  done < <(deps_of "${f}")
  # Drop any absolute rpaths configure/build may have left, then add ours.
  while IFS= read -r rp; do
    install_name_tool -delete_rpath "${rp}" "${f}" 2>/dev/null || true
  done < <(otool -l "${f}" | awk '/cmd LC_RPATH/{grab=3} grab && /path /{print $2; grab=0}')
  install_name_tool -add_rpath '@loader_path/../lib' "${f}" 2>/dev/null || true
  codesign --force --sign - "${f}" >/dev/null 2>&1 || true
}

for f in "${RUNTIME_DIR}"/bin/*; do
  is_macho "${f}" && rewrite "${f}"
done
while IFS= read -r f; do
  is_macho "${f}" && rewrite "${f}"
done < <(find "${RUNTIME_DIR}/lib" -type f \( -name '*.dylib' -o -name '*.so' \))

log "install names rewritten to @rpath/@loader_path-relative references"
