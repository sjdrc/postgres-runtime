# postgres-runtime

Builds, tests, attests, and publishes a **relocatable PostgreSQL runtime**
for the main local Go application. That is this repository's only
responsibility.

This is **not** a PostgreSQL fork or a general-purpose distribution. It is a
deterministic packaging boundary:

```text
official PostgreSQL source  →  small auditable build recipe
                            →  relocatable tested runtime
                            →  main local application
```

PostgreSQL itself is unmodified: every release is built from an official
release source tarball whose SHA-256 is pinned in [`versions.yaml`](versions.yaml)
and verified before extraction (fail-closed). `patches/` is empty by policy
and CI enforces it.

## What gets published

Per platform (see `platforms` in `versions.yaml`):

```text
postgres-runtime-<pg>+runtime.<rev>-<os>-<arch>.tar.zst          the runtime
postgres-runtime-<pg>+runtime.<rev>-<os>-<arch>.tar.zst.sha256   its checksum
postgres-runtime-<pg>+runtime.<rev>-<os>-<arch>.manifest.json    runtime manifest
postgres-runtime-<pg>+runtime.<rev>-<os>-<arch>.sbom.cdx.json    CycloneDX SBOM
```

plus a GitHub build-provenance attestation per archive. Each archive contains
a single `postgres-runtime/` directory:

```text
postgres-runtime/
├── bin/        postgres, initdb, pg_ctl, psql, pg_dump, pg_restore
├── lib/        server libraries, extension modules, bundled non-system deps
├── share/      postgres.bki, timezone data, tsearch data, extension files
└── runtime-manifest.json
```

The tree is relocatable: binaries resolve `lib/` and `share/` relative to
their own location (`$ORIGIN` RUNPATHs on Linux, `@loader_path` on macOS),
verified against a reviewed per-platform dependency allowlist. The runtime
requires **no system PostgreSQL, no package manager, and no network access**.

## Building locally

Prerequisites (Linux): `build-essential bison flex perl pkg-config patchelf
zstd jq zlib1g-dev liblz4-dev libzstd-dev` — the same list
`.github/workflows/build.yml` installs. Then:

```sh
make dist     # fetch → verify → build → stage → prune → relink →
              # verify links → manifest → package → relocation test →
              # final manifest → SBOM.   Output: work/out/
```

The smoke and relocation tests run as part of `dist` against the **packaged
archive**, extracted to a random path: initdb, start (Unix socket only, no
TCP), extension creation, the full SQL feature suite under `tests/sql/`,
pg_dump/pg_restore round-trip, clean shutdown — then the runtime directory
is **moved** and the same cluster is restarted from the new path and
re-verified. Relocation failures are release-blocking (plan §10). Tests
refuse to run as root (PostgreSQL itself does).

Useful individual targets: `make lint`, `make smoke`, `make relocation`,
`make clean` / `make distclean`.

## CI

`verify.yml` runs on every push and PR: lint, then a native build + full
test pipeline (`make dist`, including the smoke and relocation suites) for
**every** platform in `versions.yaml`, matrixed the same way `release.yml`
builds for a release. There is no separate "representative platform"
shortcut — a broken platform fails CI on the change that broke it, not
only at release time.

## Release flow

1. Update `versions.yaml` (reviewed change; the `dependency-watch` workflow
   opens an issue when upstream publishes a new patch release — it never
   auto-releases).
2. Tag `postgres-<pg-version>-runtime.<revision>` (e.g.
   `postgres-18.6-runtime.1`).
3. `release.yml` builds every platform natively, runs the full test
   pipeline per platform, verifies the artifact set as a whole
   (`scripts/verify-release-set.sh`), attests the whole set once, and
   publishes the release.

Bump `runtime.revision` when packaging or build flags change without
changing PostgreSQL; a PostgreSQL patch upgrade resets nothing else. A
PostgreSQL **major** upgrade is an application data migration and is owned
by the main application (plan §18).

## Consuming the runtime (contract summary)

The main application knows only: the runtime root, the runtime manifest,
its expected runtime version, a durable PGDATA path, and a disposable
runtime path. With `fergusstrange/embedded-postgres`:

```text
BinariesPath -> extracted postgres-runtime/ directory
DataPath     -> durable PGDATA (never inside the runtime tree)
RuntimePath  -> disposable scratch path (never PGDATA)
```

The app must verify the expected runtime version, the archive SHA-256, and
the manifest schema before use. Consumption logic lives in the main repo,
not here (plan §16, §22 milestone 5).

## Key design decisions

- **Runtime revision 1 builds without ICU, readline, and TLS** — explicit
  decisions recorded in `config/configure.common` with rationale; zlib,
  LZ4, and Zstandard are enabled and bundled. Revisit via a config change +
  runtime revision bump.
- All supplied contrib modules are built and packaged; the required set
  (`pg_trgm`, `pg_stat_statements`, `ltree`) plus `unaccent` is
  smoke-tested explicitly.
- **One third-party extension** is included under the reviewed policy in
  plan §19: [`pg_textsearch`](https://github.com/timescale/pg_textsearch)
  (BM25 ranked full-text search, permissive PostgreSQL-License, pinned to
  an exact commit). Provenance and license terms live in `versions.yaml`'s
  `third_party` section; `scripts/build-third-party.sh` fetches and
  verifies it, failing closed if the pinned commit ever doesn't match.
- The Linux ABI baseline is the glibc of the pinned CI builder
  (ubuntu-22.04). Bundled non-glibc libraries are copied into `lib/`;
  anything else outside the allowlist fails the build.

See [`SECURITY.md`](SECURITY.md), [`LICENSES.md`](LICENSES.md), and
[`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md).
