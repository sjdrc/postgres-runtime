# Implementation status

Concise status against the repository plan. Last updated: 2026-08-14.

## Summary

The full pipeline — fetch → SHA-256 verify → configure → build (server +
all contrib) → stage → prune → `$ORIGIN` relink → dependency inspection →
manifest → package → **smoke suite → relocation test** → final manifest →
SBOM — is implemented and has been executed end-to-end successfully for
**linux-amd64** against **PostgreSQL 18.6** (`make dist`). CI workflows for
verify/build/release/dependency-watch are in place and registered
(`state: active`); the files pass `actionlint` cleanly.

The first two pushes to `main` produced `startup_failure` runs (0 jobs, no
logs). The actual GitHub error, surfaced via the web UI (not visible through
the API/logs used to diagnose it here): `build.yml` declared
`id-token: write` and `attestations: write` at its workflow-level
`permissions:` block, and this repo's Actions policy caps both at `none`.
Because `verify.yml` calls `build.yml` as a reusable workflow on every push,
that unconditional top-level permission request failed validation
immediately — regardless of the (now-removed) `attest` input's value, since
GitHub validates a called workflow's declared permissions before any job
runs, not per-step conditionals. Fixed by removing attestation from
`build.yml` entirely and moving it into `release.yml`'s `publish` job as a
single attestation over the whole collected artifact set, with
`id-token: write` / `attestations: write` scoped to just that one job
(least privilege) instead of declared workflow-wide. `verify.yml` and
`build.yml` now request only `contents: read`. This does mean the
`publish` job will hit the same "not allowed" error if this repo's policy
still caps those permissions at release time — that's now isolated to a
single job on tag pushes rather than blocking everyday CI.

## Milestones (plan §22)

| Milestone | State | Notes |
| --- | --- | --- |
| 1 — one-platform proof | **Done (linux-amd64)** | Executed in a clean Linux container: fetch + pinned-SHA verify, build, stage, prune (23 MB tree, 6.1 MB archive), initdb/start/connect/stop via Unix socket only, relocation, manifest. The plan suggested darwin-arm64 first; this environment is linux-amd64, so that became the proof platform. |
| 2 — feature proof | **Done** | `tests/sql/`: FTS+GIN, pg_trgm (similarity + indexed lookup), JSONB containment + GIN, recursive CTE (incl. cyclic), COPY both directions, FOR UPDATE SKIP LOCKED, session + xact advisory locks, LISTEN/NOTIFY (cross-session, asserted on delivery), pg_stat_statements (preloaded, stats asserted), pg_dump/pg_restore round-trip with data comparison. Multi-session contention is driven deterministically via dblink. |
| 3 — Linux matrix | **Partially done** | linux-amd64 proven locally. linux-arm64 declared in `versions.yaml` + `build.yml` (native `ubuntu-22.04-arm` runner); needs its first CI run. Relocatable private-library handling + allowlisting implemented and verified on amd64. |
| 4 — release supply chain | **Implemented, unexercised** | Tag-driven `release.yml` (build matrix → `verify-release-set.sh` gate → publish), per-archive SHA-256, manifest schema + validation, CycloneDX SBOM, provenance attestation via `actions/attest-build-provenance`, weekly `dependency-watch.yml` (opens an issue; never auto-releases). Needs a first tagged release to exercise. |
| 5 — main-app consumption | **Out of scope here** | Belongs to the main Go repo (plan §22). The integration contract is documented in README; `runtime-manifest.json` ships inside every archive. |

## Definition of Done deltas (plan §24)

Verified locally for linux-amd64: items 1–23, 26–27, 33–34 (relocation
tested at two arbitrary paths with a moved tree against the same cluster;
server runs Unix-socket-only with no TCP listener; no system PostgreSQL or
network used by the packaged runtime).

Open items:

- **24/25 (linkage on all platforms):** Linux amd64 verified; arm64 and
  macOS pending first CI runs (scripts + allowlists in place).
- **28 (provenance):** wired in workflows; produced on first release.
- **30 (patch-release watcher):** implemented; fires on schedule.
- **31/32 (major upgrades, embedded-postgres wiring):** documented
  contract; owned by the main application.

## Notable decisions / caveats

- **ICU, readline, TLS are OFF for runtime revision 1** (recorded with
  rationale in `config/configure.common`; revisit = config change +
  revision bump). zlib/LZ4/Zstandard are ON and bundled into `lib/`.
- **Linux ABI baseline** is the glibc of the CI builder (ubuntu-22.04 in
  `build.yml`; the local proof used glibc 2.39). Bundled non-glibc libs are
  copied by SONAME and everything else must match the reviewed allowlist.
- `versions.yaml` platform lists use `os-arch` strings (not os/arch maps)
  to keep the auditable no-dependency parser (`scripts/lib/flatten-yaml.awk`)
  strict and small.
- The upstream `world-bin` make path skips its generated-headers ordering
  when invoked as a sub-make; `scripts/build.sh` generates headers
  explicitly first and scrubs `MAKELEVEL`/`MAKEFLAGS` (see comment there).
- pg_stat_statements assertions reset stats first: query IDs are
  jumble-based (aliases ignored), so marker queries can otherwise fold into
  pre-existing entries (see `tests/sql/post-move.sql`).

## Next steps

1. Push, open a PR, and let `verify.yml` run the lint + linux-amd64
   pipeline in CI.
2. First green runs for linux-arm64 and darwin-arm64 via
   `build.yml` (workflow_dispatch); fix any macOS-specific fallout in the
   darwin link scripts (written but not yet executed on a Mac).
3. Tag `postgres-18.6-runtime.1` to exercise the release gate, provenance,
   and publishing.
4. Consume the release from the main application (milestone 5, other repo).
