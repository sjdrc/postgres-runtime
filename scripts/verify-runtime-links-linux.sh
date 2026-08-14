#!/usr/bin/env bash
# Release-blocking Linux linkage inspection. For every ELF in the runtime
# tree, verify:
#   - RUNPATH is exactly the expected $ORIGIN-relative value;
#   - no NEEDED entry is an absolute path;
#   - every ldd-resolved dependency either lives inside the runtime tree or
#     matches the reviewed system allowlist (config/dependency-allowlist.linux);
#   - nothing is unresolved.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need readelf
need ldd

runtime="${1:-${RUNTIME_DIR}}"
[[ -d "${runtime}/bin" ]] || die "runtime tree not found: ${runtime}"
runtime_abs="$(cd "${runtime}" && pwd)"

allow=()
while IFS= read -r rx; do
  allow+=("${rx}")
done < <(read_options_file "${REPO_ROOT}/config/dependency-allowlist.linux")
[[ ${#allow[@]} -gt 0 ]] || die "empty dependency allowlist"

allowed() {
  local s="$1" rx
  for rx in "${allow[@]}"; do
    [[ "${s}" =~ ${rx} ]] && return 0
  done
  return 1
}

errors=0
fail() { printf 'LINKAGE: %s\n' "$*" >&2; errors=$((errors + 1)); }

check_elf() {
  local f="$1" want_rpath="$2" rp line name target first
  rp="$(readelf -d "${f}" | sed -n 's/.*Library r\(un\)\{0,1\}path: \[\(.*\)\]$/\2/p' | head -1)"
  if [[ "${rp}" != "${want_rpath}" ]]; then
    fail "${f}: RUNPATH is '${rp}', expected '${want_rpath}'"
  fi
  while IFS= read -r name; do
    [[ "${name}" == /* ]] && fail "${f}: NEEDED entry is an absolute path: ${name}"
  done < <(readelf -d "${f}" | awk -F'[][]' '/NEEDED/ {print $2}')
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line}" == "statically linked" ]] && continue
    if [[ "${line}" == *"=>"* ]]; then
      name="$(awk '{print $1}' <<<"${line}")"
      target="$(awk '{print $3}' <<<"${line}")"
      if [[ "${target}" == "not" || -z "${target}" ]]; then
        fail "${f}: unresolved dependency: ${name}"
      elif [[ "${target}" == "${runtime_abs}"/* ]]; then
        : # private, runtime-relative — always fine
      elif allowed "${name}"; then
        : # reviewed system library
      else
        fail "${f}: dependency outside runtime tree and allowlist: ${name} => ${target}"
      fi
    else
      first="$(awk '{print $1}' <<<"${line}")"
      allowed "${first}" || fail "${f}: unexpected dynamic entry: ${first}"
    fi
  done < <(ldd "${f}" 2>/dev/null)
}

# shellcheck disable=SC2016  # literal $ORIGIN values are what the ELF must contain
for f in "${runtime_abs}"/bin/*; do
  is_elf "${f}" && check_elf "${f}" '$ORIGIN/../lib'
done
# shellcheck disable=SC2016
while IFS= read -r f; do
  is_elf "${f}" && check_elf "${f}" '$ORIGIN'
done < <(find "${runtime_abs}/lib" -type f -name '*.so*')

[[ ${errors} -eq 0 ]] || die "${errors} linkage problem(s) found"
log "linkage OK: all dependencies are runtime-relative or on the reviewed system allowlist"
