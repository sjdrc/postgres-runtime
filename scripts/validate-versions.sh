#!/usr/bin/env bash
# Validate versions.yaml: parseable by the flattener, all required keys
# present and well-formed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

yaml_flat >/dev/null # hard-errors on unsupported syntax

pg="$(pg_version)"
[[ "${pg}" =~ ^[0-9]+\.[0-9]+$ ]] || die "postgres.version must look like MAJOR.MINOR, got: ${pg}"

fn="$(ver_get postgres.source.filename)"
[[ "${fn}" == "postgresql-${pg}.tar.bz2" ]] \
  || die "postgres.source.filename (${fn}) does not match version ${pg}"

url="$(ver_get postgres.source.url_base)"
[[ "${url}" == https://ftp.postgresql.org/pub/source/* ]] \
  || die "postgres.source.url_base must point at the official postgresql.org source area"

sha="$(ver_get postgres.source.sha256)"
[[ "${sha}" =~ ^[0-9a-f]{64}$ ]] || die "postgres.source.sha256 must be a 64-char hex digest"

rev="$(runtime_revision)"
[[ "${rev}" =~ ^[1-9][0-9]*$ ]] || die "runtime.revision must be a positive integer, got: ${rev}"

req_count="$(ver_list extensions.required | wc -l | tr -d ' ')"
[[ "${req_count}" -ge 1 ]] || die "extensions.required must not be empty"

# Third-party extensions (plan §19): every entry needs full, well-formed
# provenance — a repo URL, a ref, a 40-char pinned commit SHA, and a
# recorded license — and must also be declared required/optional so it
# actually gets smoke-tested like everything else.
while IFS= read -r name; do
  [[ -n "${name}" ]] || continue
  repo="$(ver_get "third_party.${name}.repo")"
  [[ "${repo}" == https://github.com/*.git ]] \
    || die "third_party.${name}.repo must be an https://github.com/OWNER/REPO.git URL, got: ${repo}"
  ver_get "third_party.${name}.ref" >/dev/null
  commit="$(ver_get "third_party.${name}.commit")"
  [[ "${commit}" =~ ^[0-9a-f]{40}$ ]] \
    || die "third_party.${name}.commit must be a 40-char git commit SHA, got: ${commit}"
  ver_get "third_party.${name}.license" >/dev/null
  if ! ver_list extensions.required | grep -qx "${name}" \
    && ! ver_list extensions.optional | grep -qx "${name}"; then
    die "third_party.${name} is declared but not listed in extensions.required or extensions.optional"
  fi
done < <(third_party_names)

plat_count=0
while IFS= read -r p; do
  [[ "${p}" =~ ^(linux|darwin)-(amd64|arm64)$ ]] || die "invalid platform entry: ${p}"
  plat_count=$((plat_count + 1))
done < <(ver_list platforms)
[[ "${plat_count}" -ge 1 ]] || die "platforms must not be empty"

log "versions.yaml OK: postgres ${pg}, runtime revision ${rev}, ${plat_count} platform(s)"
