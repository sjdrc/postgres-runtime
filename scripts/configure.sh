#!/usr/bin/env bash
# Extract the verified source tarball and run an out-of-tree configure with
# the source-controlled option set (config/configure.common + per-OS file).
# The effective option list is recorded for the runtime manifest.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need make
need tar
need bzip2
need perl "required by the PostgreSQL build"
need bison "required: release tarballs do not ship pre-generated parsers"
need flex "required: release tarballs do not ship pre-generated scanners"

# Always re-verify before extracting; extraction is where trust is granted.
"${SCRIPT_DIR}/verify-source.sh"

filename="$(ver_get postgres.source.filename)"
expected="$(ver_get postgres.source.sha256)"
tarball="${DIST_DIR}/${filename}"
stamp="${SOURCE_DIR}/.extracted-sha256"

if [[ ! -f "${stamp}" || "$(cat "${stamp}")" != "${expected}" ]]; then
  log "extracting ${filename}"
  rm -rf "${SOURCE_DIR}"
  mkdir -p "${SOURCE_DIR}"
  tar -xjf "${tarball}" -C "${SOURCE_DIR}" --strip-components=1
  printf '%s\n' "${expected}" > "${stamp}"
fi

os="$(host_platform)"
os="${os%%-*}"

opts=()
while IFS= read -r line; do
  opts+=("${line}")
done < <(
  read_options_file "${REPO_ROOT}/config/configure.common"
  read_options_file "${REPO_ROOT}/config/configure.${os}"
)

# Homebrew's prefix differs by Mac architecture (/opt/homebrew on Apple
# Silicon, /usr/local on Intel); detect it rather than hard-coding either,
# since both darwin-arm64 and darwin-amd64 build natively in CI.
if [[ "${os}" == darwin ]] && command -v brew >/dev/null 2>&1; then
  brew_prefix="$(brew --prefix)"
  opts+=("--with-libraries=${brew_prefix}/lib" "--with-includes=${brew_prefix}/include")
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
log "configuring with prefix ${PG_PREFIX} and options: ${opts[*]}"
(cd "${BUILD_DIR}" && "${SOURCE_DIR}/configure" --prefix="${PG_PREFIX}" "${opts[@]}")

mkdir -p "${WORK_DIR}"
{
  printf -- '--prefix=%s\n' "${PG_PREFIX}"
  printf '%s\n' "${opts[@]}"
} > "${WORK_DIR}/configure-options.txt"
log "configure complete; effective options recorded in work/configure-options.txt"
