#!/usr/bin/env bash
# Verify the downloaded source tarball against the SHA-256 pinned in
# versions.yaml. Fails closed on any mismatch.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

filename="$(ver_get postgres.source.filename)"
expected="$(ver_get postgres.source.sha256)"
tarball="${DIST_DIR}/${filename}"

[[ -f "${tarball}" ]] || die "source tarball not found: ${tarball} (run scripts/fetch-source.sh)"
[[ "${expected}" =~ ^[0-9a-f]{64}$ ]] || die "pinned sha256 in versions.yaml is not a 64-char hex digest"

actual="$(sha256_file "${tarball}")"
if [[ "${actual}" != "${expected}" ]]; then
  die "source checksum mismatch for ${filename}
  expected: ${expected}
  actual:   ${actual}
Refusing to continue. Delete the file and re-fetch, or fix the pin via a reviewed change."
fi
log "source checksum OK: ${filename} ${actual}"
