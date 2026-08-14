#!/usr/bin/env bash
# Release gate (plan §14 release.yml): given a directory of collected build
# artifacts and the release tag, verify that every platform in versions.yaml
# has an archive, checksum, and manifest; that checksums match; and that
# all manifests agree on the PostgreSQL version and runtime revision.
#
#   verify-release-set.sh <artifact-dir> <tag>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need jq

dir="${1:-}"
tag="${2:-}"
[[ -n "${dir}" && -d "${dir}" && -n "${tag}" ]] || die "usage: verify-release-set.sh <artifact-dir> <tag>"

pg="$(pg_version)"
rev="$(runtime_revision)"
rv="$(runtime_version)"

expected_tag="postgres-${pg}-runtime.${rev}"
[[ "${tag}" == "${expected_tag}" ]] \
  || die "tag ${tag} does not match versions.yaml (expected ${expected_tag})"

while IFS= read -r platform; do
  base="postgres-runtime-${rv}-${platform}"
  archive="${dir}/${base}.tar.zst"
  shafile="${archive}.sha256"
  manifest="${dir}/${base}.manifest.json"

  for f in "${archive}" "${shafile}" "${manifest}"; do
    [[ -f "${f}" ]] || die "required release artifact missing: ${f}"
  done

  actual="$(sha256_file "${archive}")"
  recorded="$(awk '{print $1}' "${shafile}")"
  [[ "${actual}" == "${recorded}" ]] \
    || die "${base}: archive checksum mismatch (recorded ${recorded}, actual ${actual})"

  "${SCRIPT_DIR}/validate-manifest.sh" "${manifest}"
  jq -e --arg pg "${pg}" --argjson rev "${rev}" --arg p "${platform}" --arg sha "${actual}" '
    .postgres_version == $pg
    and .runtime_revision == $rev
    and .platform == $p
    and .runtime.archive_sha256 == $sha
  ' "${manifest}" >/dev/null \
    || die "${base}: manifest disagrees with versions.yaml or archive checksum"

  log "release artifact OK: ${base}"
done < <(ver_list platforms)

log "release set OK for ${expected_tag}"
