#!/usr/bin/env bash
# Mandatory runtime smoke tests (plan §9). Runs against an extracted
# runtime tree using only the packaged binaries, a Unix socket, and no
# TCP listener — proving offline, local-only operation.
#
#   smoke-test.sh --runtime DIR --workdir DIR [--phase full|essential]
#
#   full      initdb a fresh cluster, start, create extensions, run every
#             application-relevant SQL test, exercise pg_dump/pg_restore,
#             shut down cleanly. Cluster state is left in WORKDIR for a
#             subsequent essential phase.
#   essential restart the existing cluster (after the runtime tree has been
#             moved) and re-run the essential feature checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

runtime=""
workdir=""
phase="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime) runtime="$2"; shift 2 ;;
    --workdir) workdir="$2"; shift 2 ;;
    --phase) phase="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ -n "${runtime}" && -n "${workdir}" ]] || die "usage: smoke-test.sh --runtime DIR --workdir DIR [--phase full|essential]"
[[ "${phase}" == full || "${phase}" == essential ]] || die "invalid phase: ${phase}"
[[ -x "${runtime}/bin/postgres" ]] || die "not a runtime tree (no bin/postgres): ${runtime}"
if [[ "$(id -u)" -eq 0 ]]; then
  die "PostgreSQL refuses to run as root; run the smoke test as an unprivileged user"
fi

runtime="$(cd "${runtime}" && pwd)"
mkdir -p "${workdir}"
workdir="$(cd "${workdir}" && pwd)"
bin="${runtime}/bin"
pgdata="${workdir}/data"
logfile="${workdir}/postgres-${phase}.log"
sqldir="${REPO_ROOT}/tests/sql"

# Short private socket directory (socket paths have a ~100 char limit).
sock="$(mktemp -d "${TMPDIR:-/tmp}/pgrt.XXXXXX")"

# Strip library-path variables so nothing outside the runtime tree can
# satisfy a dependency by accident.
run() {
  env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH "$@"
}

server_running=no
cleanup() {
  if [[ "${server_running}" == yes ]]; then
    run "${bin}/pg_ctl" -D "${pgdata}" -m fast -w -t 30 stop >/dev/null 2>&1 || true
  fi
  rm -rf "${sock}"
}
trap cleanup EXIT

psql_run() { # psql_run <db> <args...>
  local db="$1"
  shift
  run "${bin}/psql" -h "${sock}" -U postgres -d "${db}" \
    --no-psqlrc -v ON_ERROR_STOP=1 "$@"
}

start_server() {
  log "starting postgres (unix socket only, pg_stat_statements preloaded)"
  run "${bin}/pg_ctl" -D "${pgdata}" -l "${logfile}" -w -t 60 \
    -o "-c listen_addresses='' -c unix_socket_directories='${sock}' -c shared_preload_libraries='pg_stat_statements'" \
    start >/dev/null
  server_running=yes
}

stop_server() {
  run "${bin}/pg_ctl" -D "${pgdata}" -m fast -w -t 60 stop >/dev/null
  server_running=no
}

# Doctor-style sanity: the binary's version must match the manifest.
if [[ -f "${runtime}/runtime-manifest.json" ]] && command -v jq >/dev/null 2>&1; then
  expected_pg="$(jq -r .postgres_version "${runtime}/runtime-manifest.json")"
  actual_pg="$(run "${bin}/postgres" --version)"
  [[ "${actual_pg}" == *" ${expected_pg}"* ]] \
    || die "postgres --version ('${actual_pg}') does not match manifest version ${expected_pg}"
fi

conninfo_for() { printf 'host=%s dbname=%s user=postgres' "${sock}" "$1"; }

if [[ "${phase}" == full ]]; then
  log "initdb: fresh cluster at ${pgdata}"
  rm -rf "${pgdata}"
  run "${bin}/initdb" --pgdata "${pgdata}" -U postgres --auth trust \
    --encoding UTF8 --locale C >/dev/null

  start_server
  psql_run postgres -q -c 'CREATE DATABASE smoke' >/dev/null

  # Order matters: extensions.sql first (creates required extensions and
  # the dblink test harness used by the multi-session tests).
  for f in extensions core jsonb fulltext trigram recursive-cte \
    skip-locked advisory-lock pg-stat-statements; do
    log "sql test: ${f}.sql"
    psql_run smoke -q -v conninfo="$(conninfo_for smoke)" \
      -f "${sqldir}/${f}.sql" >/dev/null
  done

  # LISTEN/NOTIFY: psql prints received notifications; assert on them.
  log "sql test: listen-notify.sql"
  ln_out="$(psql_run smoke -v conninfo="$(conninfo_for smoke)" \
    -f "${sqldir}/listen-notify.sql" 2>&1)"
  grep -q 'Asynchronous notification "smoke_events" with payload "cross-session-ping"' <<<"${ln_out}" \
    || die "cross-session NOTIFY was not received: ${ln_out}"
  grep -q 'Asynchronous notification "smoke_events" with payload "same-session-ping"' <<<"${ln_out}" \
    || die "same-session NOTIFY was not received: ${ln_out}"

  # Backup/restore with the packaged tooling (plan §9.4).
  log "backup/restore: pg_dump -> pg_restore -> verify"
  dump="${workdir}/smoke.dump"
  run "${bin}/pg_dump" -h "${sock}" -U postgres -Fc -f "${dump}" smoke
  psql_run postgres -q -c 'DROP DATABASE IF EXISTS smoke_restore' >/dev/null
  psql_run postgres -q -c 'CREATE DATABASE smoke_restore' >/dev/null
  run "${bin}/pg_restore" -h "${sock}" -U postgres --exit-on-error --no-owner \
    -d smoke_restore "${dump}"
  checks=(
    'SELECT count(*) FROM parent'
    'SELECT count(*) FROM child'
    'SELECT count(*) FROM tasks'
    'SELECT count(*) FROM queue'
    'SELECT count(*) FROM docs'
    'SELECT count(*) FROM events'
    'SELECT count(*) FROM names'
    'SELECT count(*) FROM paths'
    'SELECT string_agg(extname, chr(44) ORDER BY extname) FROM pg_extension'
  )
  for q in "${checks[@]}"; do
    a="$(psql_run smoke -qtA -c "${q}")"
    b="$(psql_run smoke_restore -qtA -c "${q}")"
    [[ "${a}" == "${b}" && -n "${a}" ]] \
      || die "restore verification failed for [${q}]: '${a}' vs '${b}'"
  done

  stop_server
  log "smoke tests passed (full phase); cluster preserved at ${pgdata}"
else
  [[ -d "${pgdata}" ]] || die "essential phase requires an existing cluster at ${pgdata}"
  start_server

  log "sql test: post-move.sql (data + extensions survive relocation)"
  psql_run smoke -q -f "${sqldir}/post-move.sql" >/dev/null

  # Extension installation must still work from the moved tree.
  psql_run postgres -q -c 'DROP DATABASE IF EXISTS reloc_check' >/dev/null
  psql_run postgres -q -c 'CREATE DATABASE reloc_check' >/dev/null
  psql_run reloc_check -q -c 'CREATE EXTENSION pg_trgm' >/dev/null
  sim="$(psql_run reloc_check -qtA -c "SELECT similarity('postgres','postgras') > 0.3")"
  [[ "${sim}" == t ]] || die "pg_trgm not functional after relocation"
  psql_run postgres -q -c 'DROP DATABASE reloc_check' >/dev/null

  # pg_dump still works from the moved tree.
  run "${bin}/pg_dump" -h "${sock}" -U postgres --schema-only -f "${workdir}/post-move.sql.dump" smoke
  [[ -s "${workdir}/post-move.sql.dump" ]] || die "post-move pg_dump produced no output"

  stop_server
  log "smoke tests passed (essential phase)"
fi
