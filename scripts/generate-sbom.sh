#!/usr/bin/env bash
# Generate a minimal CycloneDX SBOM for the runtime artifact: the pinned
# PostgreSQL source plus every bundled (non-system) shared library.
# Deliberately small and dependency-free (jq only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need jq

[[ -d "${RUNTIME_DIR}" ]] || die "runtime tree not found (run scripts/prune-stage.sh)"
mkdir -p "${OUT_DIR}"

os="$(host_platform)"
os="${os%%-*}"

license_for() {
  case "$1" in
    libz.*) echo "Zlib" ;;
    liblz4.*) echo "BSD-2-Clause" ;;
    libzstd.*) echo "BSD-3-Clause" ;;
    *) echo "NOASSERTION" ;;
  esac
}

bundled_components="$(
  while IFS= read -r name; do
    f="${RUNTIME_DIR}/lib/${name}"
    [[ -f "${f}" ]] || die "bundled library listed but not present in runtime: ${name}"
    jq -n --arg name "${name}" --arg sha "$(sha256_file "${f}")" \
      --arg lic "$(license_for "${name}")" \
      '{type: "library", name: $name, version: "bundled",
        hashes: [{alg: "SHA-256", content: $sha}],
        licenses: [{license: {name: $lic}}]}'
  done < <(read_options_file "${REPO_ROOT}/config/bundled-libs.${os}") | jq -s .
)"

out="${OUT_DIR}/$(artifact_name).sbom.cdx.json"
jq -n \
  --arg rv "$(runtime_version)" \
  --arg pg "$(pg_version)" \
  --arg srcsha "$(ver_get postgres.source.sha256)" \
  --argjson bundled "${bundled_components}" \
  '{
    bomFormat: "CycloneDX",
    specVersion: "1.5",
    version: 1,
    metadata: {component: {type: "application", name: "postgres-runtime", version: $rv}},
    components: ([
      {type: "application", name: "postgresql", version: $pg,
       purl: ("pkg:generic/postgresql@" + $pg),
       hashes: [{alg: "SHA-256", content: $srcsha}],
       licenses: [{license: {name: "PostgreSQL"}}]}
    ] + $bundled)
  }' > "${out}"
log "wrote ${out}"
