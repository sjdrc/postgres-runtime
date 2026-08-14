#!/usr/bin/env bash
# Shared helpers for postgres-runtime scripts. Source this; do not execute.
# shellcheck disable=SC2034  # variables here are consumed by sourcing scripts
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/work}"
DIST_DIR="${WORK_DIR}/dist"
SOURCE_DIR="${WORK_DIR}/source"
BUILD_DIR="${WORK_DIR}/build"
STAGE_DIR="${WORK_DIR}/stage"
RUNTIME_PARENT="${WORK_DIR}/runtime"
RUNTIME_DIR="${RUNTIME_PARENT}/postgres-runtime"
OUT_DIR="${WORK_DIR}/out"

VERSIONS_FILE="${REPO_ROOT}/versions.yaml"

# Install prefix compiled into the binaries. PostgreSQL derives every other
# path from the location of the running executable as long as the relative
# bin/lib/share layout matches this prefix — that is what makes the tree
# relocatable. The prefix must contain "postgres" so upstream omits the
# extra share/postgresql and lib/postgresql subdirectories.
PG_PREFIX="/opt/postgres-runtime"

# The exact binaries the runtime ships (plan §7 / Definition of Done).
RUNTIME_TOOLS=(postgres initdb pg_ctl psql pg_dump pg_restore)

log() { printf '>> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1${2:+ ($2)}"; }

yaml_flat() { awk -f "${REPO_ROOT}/scripts/lib/flatten-yaml.awk" "${VERSIONS_FILE}"; }

# ver_get <dotted.key> — print the scalar at key, fail if absent.
ver_get() {
  local out
  out="$(yaml_flat | awk -v p="$1=" 'index($0, p) == 1 { print substr($0, length(p) + 1); exit }')"
  [[ -n "${out}" ]] || die "versions.yaml: missing key: $1"
  printf '%s\n' "${out}"
}

# ver_list <dotted.key> — print list items at key, one per line.
ver_list() {
  yaml_flat | awk -v p="$1[]=" 'index($0, p) == 1 { print substr($0, length(p) + 1) }'
}

pg_version() { ver_get postgres.version; }
runtime_revision() { ver_get runtime.revision; }
runtime_version() { printf '%s+runtime.%s\n' "$(pg_version)" "$(runtime_revision)"; }

host_platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  printf '%s-%s\n' "${os}" "${arch}"
}

artifact_name() { printf 'postgres-runtime-%s-%s\n' "$(runtime_version)" "$(host_platform)"; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi | awk '{print $1}'
}

build_commit() { git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown; }

# Timestamp used for normalized archive mtimes and manifest built_at.
source_epoch() {
  if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
    printf '%s\n' "${SOURCE_DATE_EPOCH}"
  else
    git -C "${REPO_ROOT}" log -1 --format=%ct 2>/dev/null || echo 1704067200
  fi
}

iso_utc() {
  local e="$1"
  if date -u -d "@${e}" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "@${e}" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -r "${e}" +%Y-%m-%dT%H:%M:%SZ
  fi
}

is_elf() {
  [[ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]]
}

# read_options_file <file> — print effective lines (comments/blanks stripped).
read_options_file() {
  [[ -f "$1" ]] || return 0
  grep -Ev '^[[:space:]]*(#|$)' "$1" || true
}
