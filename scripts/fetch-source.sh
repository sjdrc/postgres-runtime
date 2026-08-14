#!/usr/bin/env bash
# Download the pinned official PostgreSQL source tarball into work/dist.
# Verification is a separate, mandatory step (verify-source.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need curl

filename="$(ver_get postgres.source.filename)"
url_base="$(ver_get postgres.source.url_base)"
tarball="${DIST_DIR}/${filename}"

mkdir -p "${DIST_DIR}"

if [[ -f "${tarball}" ]]; then
  log "source already present: ${tarball} (checksum is verified separately)"
  exit 0
fi

url="${url_base}/${filename}"
log "fetching ${url}"
curl -fSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
  -o "${tarball}.part" "${url}"
mv "${tarball}.part" "${tarball}"
log "downloaded ${tarball}"
