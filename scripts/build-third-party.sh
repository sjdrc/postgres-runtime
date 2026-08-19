#!/usr/bin/env bash
# Build and install every third-party extension declared under
# versions.yaml's `third_party` section (plan §19). Each one is fetched by
# cloning the pinned tag and verifying the resulting commit matches the
# pinned commit SHA exactly (fail closed on mismatch — the equivalent of
# source-tarball SHA-256 verification for a git-hosted dependency), then
# built via PGXS against this repo's own freshly staged PostgreSQL and
# installed into that same staging prefix, so it is picked up by
# prune-stage.sh's existing per-extension validation and by the
# Linux/macOS relinking scripts with no changes to either.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need git
need make

pg_config="${STAGE_DIR}${PG_PREFIX}/bin/pg_config"
[[ -x "${pg_config}" ]] || die "staged pg_config not found (run scripts/install-stage.sh first): ${pg_config}"

names="$(third_party_names)"
if [[ -z "${names}" ]]; then
  log "no third-party extensions declared; nothing to build"
  exit 0
fi

src_root="${WORK_DIR}/third-party"
rm -rf "${src_root}"
mkdir -p "${src_root}"

jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

while IFS= read -r name; do
  [[ -n "${name}" ]] || continue
  repo="$(ver_get "third_party.${name}.repo")"
  ref="$(ver_get "third_party.${name}.ref")"
  expected_commit="$(ver_get "third_party.${name}.commit")"
  [[ "${expected_commit}" =~ ^[0-9a-f]{40}$ ]] || die "third_party.${name}.commit must be a 40-character git commit SHA"

  dir="${src_root}/${name}"
  log "fetching ${name} ${ref} from ${repo}"
  git clone --quiet --depth 1 --branch "${ref}" "${repo}" "${dir}"

  actual_commit="$(git -C "${dir}" rev-parse HEAD)"
  if [[ "${actual_commit}" != "${expected_commit}" ]]; then
    die "third-party source commit mismatch for ${name}
  expected: ${expected_commit}
  actual:   ${actual_commit}
Refusing to build. Either ref ${ref} was force-moved upstream (treat as
suspicious until confirmed otherwise) or the pin in versions.yaml is
stale — fix via a reviewed change, never by silently trusting whatever
the ref currently resolves to."
  fi
  log "${name} source verified at ${actual_commit}"

  log "building ${name} against ${pg_config}"
  make -C "${dir}" -j"${jobs}" PG_CONFIG="${pg_config}" >/dev/null
  make -C "${dir}" install PG_CONFIG="${pg_config}" DESTDIR="${STAGE_DIR}" >/dev/null
  log "${name} installed into stage"
done <<<"${names}"
