# Implementation status

Concise status against the repository plan. Last updated: 2026-08-19.

## Summary

The full pipeline — fetch → SHA-256 verify → configure → build (server +
all contrib) → stage → prune → `$ORIGIN` relink → dependency inspection →
manifest → package → **smoke suite → relocation test** → final manifest →
SBOM — is implemented and has been executed end-to-end successfully for
**linux-amd64** against **PostgreSQL 18.6** (`make dist`). CI workflows for
verify/build/release/dependency-watch are in place and registered
(`state: active`); the files pass `actionlint` cleanly. `versions.yaml`
declares four platforms — `linux-amd64`, `linux-arm64`, `darwin-arm64`,
`darwin-amd64` — and `verify.yml` now builds and fully tests **all of
them** natively on every push/PR (matrixed the same way `release.yml`
builds for a release), not just a single representative platform.

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

`config/configure.darwin` previously hard-coded `/opt/homebrew` (Apple
Silicon's Homebrew prefix) for the lz4/zstd search paths — correct for
`darwin-arm64` but wrong for `darwin-amd64` (Intel Homebrew uses
`/usr/local`), a latent bug that would have surfaced silently the first
time that platform actually built. Fixed by having `scripts/configure.sh`
detect the prefix via `brew --prefix` at configure time instead of
hard-coding either path.

No release has been tagged yet, so nothing has been published as
downloadable GitHub Release assets — `verify.yml` only uploads short-lived
workflow-run artifacts (~90-day retention), not a Release. Publishing a
Release requires pushing a `postgres-<version>-runtime.<revision>` tag to
trigger `release.yml`.

First real matrix run on CI (commit `353e2e8`): `linux-amd64` and
`linux-arm64` both went fully green (build, smoke suite, relocation test,
upload). `darwin-arm64` failed `verify-runtime-links-darwin.sh` with a real
bug: PostgreSQL's own build sets `libpq.5.dylib`'s own install name
(`LC_ID_DYLIB`) to the absolute `--prefix` path
(`/opt/postgres-runtime/lib/libpq.5.dylib`).
`rewrite-runtime-links-darwin.sh` rewrote every *dependent's* reference to
that path (via `install_name_tool -change`) but never reset the library's
own ID — `-change` only touches `LC_LOAD_DYLIB`-family commands, not a
library's own `LC_ID_DYLIB`. Fixed by explicitly setting
`install_name_tool -id @rpath/<basename>` on every `.dylib` under `lib/`
(harmlessly a no-op for `-bundle`-type contrib extension modules, which
have no `LC_ID_DYLIB` to set). `darwin-amd64` never got a runner allocated before this fix landed
(queued indefinitely, `runner_id: 0`) — root cause turned out to be
separate: `build.yml` targeted the `macos-13` runner label, which was
fully retired in December 2025. Fixed by switching to `macos-15-intel`,
the current GitHub-hosted x86_64 macOS label (itself scheduled for
retirement in Fall 2027, when GitHub drops Intel macOS support).

With both fixes in, all four platforms went fully green on
`verify.yml` (commit `a39f845`): lint, build, full smoke suite, and
relocation test, each on its native runner. `postgres-18.6-runtime.1`
was then tagged and `release.yml` published it as a real GitHub Release
with all four archives, checksums, manifests, SBOMs, and a provenance
attestation.

**pg_textsearch (third-party extension, plan §19).** Added BM25 ranked
full-text search via [timescale/pg_textsearch](https://github.com/timescale/pg_textsearch)
v1.4.0, pinned to its exact commit. License reviewed: PostgreSQL License
(permissive). A second third-party extension, ParadeDB's `pg_search`, was
evaluated and deliberately **not** added — it's AGPL-3.0 with no
commercial license terms in the public repo (AGPL's network-use clause
could obligate the whole main application to open its source if ever
network-exposed) and is Rust/pgrx-based, a much heavier build toolchain
than anything else in this repo. `pg_textsearch` by contrast is pure C,
builds via plain PGXS against this repo's own staged PostgreSQL with zero
external dependencies (confirmed: linkage is libc-only), and required no
changes to the Linux/macOS relinking scripts — the existing generic
per-file loops picked it up automatically. `scripts/build-third-party.sh`
clones the pinned ref and fails closed if the resulting commit doesn't
match the pinned SHA, mirroring the source-tarball SHA-256 verification
already used for PostgreSQL itself. Bumped `runtime.revision` to 2 (adding
an extension is a packaging change, not a PostgreSQL version change).
Validated locally end-to-end (build, prune's existing extension checks,
linkage verification, full smoke suite including a dedicated BM25 ranking
+ index-usage test, backup/restore round-trip, and post-relocation
re-verification) before pushing; not yet exercised on CI.

## Milestones (plan §22)

| Milestone | State | Notes |
| --- | --- | --- |
| 1 — one-platform proof | **Done (linux-amd64)** | Executed in a clean Linux container: fetch + pinned-SHA verify, build, stage, prune (23 MB tree, 6.1 MB archive), initdb/start/connect/stop via Unix socket only, relocation, manifest. The plan suggested darwin-arm64 first; this environment is linux-amd64, so that became the proof platform. |
| 2 — feature proof | **Done** | `tests/sql/`: FTS+GIN, pg_trgm (similarity + indexed lookup), JSONB containment + GIN, recursive CTE (incl. cyclic), COPY both directions, FOR UPDATE SKIP LOCKED, session + xact advisory locks, LISTEN/NOTIFY (cross-session, asserted on delivery), pg_stat_statements (preloaded, stats asserted), pg_dump/pg_restore round-trip with data comparison. Multi-session contention is driven deterministically via dblink. |
| 3 — full platform matrix | **Done** | All four platforms (`linux-amd64`, `linux-arm64`, `darwin-arm64`, `darwin-amd64`) build+test natively on every `verify.yml` run and have gone fully green on real CI runners. Relocatable private-library handling + allowlisting verified on Linux and macOS both. |
| 4 — release supply chain | **Done (exercised once)** | Tag-driven `release.yml` (build matrix → `verify-release-set.sh` gate → publish), per-archive SHA-256, manifest schema + validation, CycloneDX SBOM, provenance attestation via `actions/attest-build-provenance`, weekly `dependency-watch.yml` (opens an issue; never auto-releases). `postgres-18.6-runtime.1` is published with all four platform archives. `postgres-18.6-runtime.2` (adding pg_textsearch) is pending a tag. |
| 5 — main-app consumption | **Out of scope here** | Belongs to the main Go repo (plan §22). The integration contract is documented in README; `runtime-manifest.json` ships inside every archive. |

## Definition of Done deltas (plan §24)

Verified locally for linux-amd64: items 1–23, 26–27, 33–34 (relocation
tested at two arbitrary paths with a moved tree against the same cluster;
server runs Unix-socket-only with no TCP listener; no system PostgreSQL or
network used by the packaged runtime).

Verified on CI across all four platforms: items 24/25 (linkage), 28
(provenance — produced and attached on the `postgres-18.6-runtime.1`
release).

Open items:

- **30 (patch-release watcher):** implemented; fires on schedule, not yet
  observed firing for real (no upstream patch release since it was added).
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

1. Tag `postgres-18.6-runtime.2` to publish the pg_textsearch addition as
   a real release (mirrors how `postgres-18.6-runtime.1` was published).
2. Consume a release from the main application (milestone 5, other repo).
3. If a future third-party extension is ever proposed, reuse the
   `pg_textsearch` review as the template: license first, build-toolchain
   weight second, only then implementation.
