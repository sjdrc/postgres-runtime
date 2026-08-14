#!/usr/bin/env bash
# Package the runtime tree as a zstd-compressed tarball with a single
# top-level "postgres-runtime/" directory. With GNU tar the archive is
# normalized (sorted names, uid/gid 0, fixed mtime) for reproducibility.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need zstd

[[ -d "${RUNTIME_DIR}" ]] || die "runtime tree not found (run scripts/prune-stage.sh)"
[[ -f "${RUNTIME_DIR}/runtime-manifest.json" ]] || die "runtime-manifest.json missing (run scripts/generate-manifest.sh prelim)"

mkdir -p "${OUT_DIR}"
name="$(artifact_name).tar.zst"
out="${OUT_DIR}/${name}"

TAR=tar
command -v gtar >/dev/null 2>&1 && TAR=gtar

emit_tar() {
  if "${TAR}" --version 2>/dev/null | grep -q 'GNU tar'; then
    "${TAR}" --sort=name --owner=0 --group=0 --numeric-owner \
      --mtime="@$(source_epoch)" \
      -C "${RUNTIME_PARENT}" -cf - postgres-runtime
  else
    log "warning: GNU tar not found; archive will not be normalized"
    "${TAR}" -C "${RUNTIME_PARENT}" -cf - postgres-runtime
  fi
}

log "packaging ${name} (zstd level ${ZSTD_LEVEL:-19})"
emit_tar | zstd -q -T0 "-${ZSTD_LEVEL:-19}" -f -o "${out}"

sha="$(sha256_file "${out}")"
printf '%s  %s\n' "${sha}" "${name}" > "${out}.sha256"
log "wrote ${out} ($(du -h "${out}" | cut -f1)) sha256=${sha}"
