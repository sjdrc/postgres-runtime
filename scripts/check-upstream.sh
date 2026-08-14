#!/usr/bin/env bash
# Check postgresql.org for a newer patch release within the pinned major
# version. Prints the newer version (e.g. "18.7") to stdout if one exists,
# otherwise prints nothing. Never changes anything by itself — the
# dependency-watch workflow turns a detection into an issue for review.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need curl

current="$(pg_version)"
major="${current%%.*}"

listing="$(curl -fsSL --max-time 60 "https://www.postgresql.org/ftp/source/")"
latest="$(grep -oE "v${major}\.[0-9]+" <<<"${listing}" | sort -uV | tail -1 || true)"
latest="${latest#v}"

[[ -n "${latest}" ]] || die "could not determine latest ${major}.x release from postgresql.org"

if [[ "${latest}" != "${current}" && \
  "$(printf '%s\n%s\n' "${current}" "${latest}" | sort -V | tail -1)" == "${latest}" ]]; then
  log "newer upstream release available: ${latest} (pinned: ${current})"
  printf '%s\n' "${latest}"
else
  log "pinned version ${current} is current"
fi
