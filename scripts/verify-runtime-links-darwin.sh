#!/usr/bin/env bash
# Release-blocking macOS linkage inspection. For every Mach-O file in the
# runtime tree, verify via `otool -L` / `otool -l` that:
#   - every reference is an Apple system location (config/
#     dependency-allowlist.darwin) or an @rpath/@loader_path reference that
#     resolves inside runtime/lib;
#   - no reference points at Homebrew, /usr/local, build prefixes, or any
#     other absolute non-system path;
#   - LC_RPATH entries are @loader_path-relative only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need otool

runtime="${1:-${RUNTIME_DIR}}"
[[ -d "${runtime}/bin" ]] || die "runtime tree not found: ${runtime}"
runtime_abs="$(cd "${runtime}" && pwd)"

allow=()
while IFS= read -r rx; do
  allow+=("${rx}")
done < <(read_options_file "${REPO_ROOT}/config/dependency-allowlist.darwin")
[[ ${#allow[@]} -gt 0 ]] || die "empty dependency allowlist"

allowed() {
  local s="$1" rx
  for rx in "${allow[@]}"; do
    [[ "${s}" =~ ${rx} ]] && return 0
  done
  return 1
}

is_macho() { otool -h "$1" >/dev/null 2>&1; }

errors=0
fail() { printf 'LINKAGE: %s\n' "$*" >&2; errors=$((errors + 1)); }

check_macho() {
  local f="$1" dep base rp
  while IFS= read -r dep; do
    if [[ "${dep}" == @rpath/* || "${dep}" == @loader_path/* ]]; then
      base="$(basename "${dep}")"
      [[ -f "${runtime_abs}/lib/${base}" ]] \
        || fail "${f}: ${dep} does not resolve inside runtime/lib"
    elif allowed "${dep}"; then
      :
    else
      fail "${f}: non-system absolute reference: ${dep}"
    fi
  done < <(otool -L "${f}" | awk 'NR > 1 {print $1}')
  while IFS= read -r rp; do
    [[ "${rp}" == @loader_path/* ]] || fail "${f}: non-relative LC_RPATH: ${rp}"
  done < <(otool -l "${f}" | awk '/cmd LC_RPATH/{grab=3} grab && /path /{print $2; grab=0}')
}

for f in "${runtime_abs}"/bin/*; do
  is_macho "${f}" && check_macho "${f}"
done
while IFS= read -r f; do
  is_macho "${f}" && check_macho "${f}"
done < <(find "${runtime_abs}/lib" -type f \( -name '*.dylib' -o -name '*.so' \))

[[ ${errors} -eq 0 ]] || die "${errors} linkage problem(s) found"
log "linkage OK: only Apple system and runtime-relative references present"
