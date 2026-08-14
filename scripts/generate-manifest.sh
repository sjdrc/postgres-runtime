#!/usr/bin/env bash
# Generate the runtime manifest (runtime-manifest.schema.json).
#   prelim — write runtime-manifest.json inside the runtime tree, so the
#            packaged archive carries its own metadata (no archive fields).
#   final <archive> — write the sidecar release manifest next to the
#            archive, adding runtime.archive_sha256.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need jq

mode="${1:-prelim}"

opts_file="${WORK_DIR}/configure-options.txt"
[[ -f "${opts_file}" ]] || die "missing ${opts_file} (run scripts/configure.sh)"

opts_json="$(jq -Rn '[inputs]' < "${opts_file}")"
ext_json="$(
  {
    ver_list extensions.required | jq -R '{name: ., required: true}'
    ver_list extensions.optional | jq -R '{name: ., required: false}'
  } | jq -s .
)"
tools_json="$(printf '%s\n' "${RUNTIME_TOOLS[@]}" | jq -R . | jq -s .)"

base_manifest() {
  jq -n \
    --arg pg "$(pg_version)" \
    --argjson rev "$(runtime_revision)" \
    --arg rv "$(runtime_version)" \
    --arg platform "$(host_platform)" \
    --arg sf "$(ver_get postgres.source.filename)" \
    --arg ss "$(ver_get postgres.source.sha256)" \
    --arg commit "$(build_commit)" \
    --arg built "$(iso_utc "$(source_epoch)")" \
    --argjson co "${opts_json}" \
    --argjson ext "${ext_json}" \
    --argjson tools "${tools_json}" \
    '{
      schema_version: 1,
      postgres_version: $pg,
      runtime_revision: $rev,
      runtime_version: $rv,
      platform: $platform,
      source: {filename: $sf, sha256: $ss},
      runtime: {build_commit: $commit, built_at: $built},
      configure_options: $co,
      extensions: $ext,
      tools: $tools
    }'
}

case "${mode}" in
  prelim)
    [[ -d "${RUNTIME_DIR}" ]] || die "runtime tree not found (run scripts/prune-stage.sh)"
    base_manifest > "${RUNTIME_DIR}/runtime-manifest.json"
    log "wrote ${RUNTIME_DIR}/runtime-manifest.json"
    ;;
  final)
    archive="${2:-${OUT_DIR}/$(artifact_name).tar.zst}"
    [[ -f "${archive}" ]] || die "archive not found: ${archive} (run scripts/package.sh)"
    prelim="${RUNTIME_DIR}/runtime-manifest.json"
    [[ -f "${prelim}" ]] || die "preliminary manifest not found: ${prelim}"
    sha="$(sha256_file "${archive}")"
    mkdir -p "${OUT_DIR}"
    out="${OUT_DIR}/$(artifact_name).manifest.json"
    jq --arg sha "${sha}" '.runtime.archive_sha256 = $sha' "${prelim}" > "${out}"
    "${SCRIPT_DIR}/validate-manifest.sh" "${out}"
    log "wrote ${out}"
    ;;
  *)
    die "usage: generate-manifest.sh [prelim | final <archive>]"
    ;;
esac
