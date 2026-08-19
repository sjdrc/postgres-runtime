# Security

## Threat model & posture

This repository packages an **unmodified official PostgreSQL release** into a
relocatable runtime for a local, offline application. The security posture
follows from that:

- **Source integrity.** The only build input is the official PostgreSQL
  release tarball, pinned by SHA-256 in `versions.yaml` and verified
  fail-closed before extraction. No mirrors, no floating refs.
- **No patches.** `patches/` must stay empty (CI-enforced). Any future patch
  follows the policy in `patches/README.md`.
- **Local-only server.** The runtime is smoke-tested with
  `listen_addresses=''` and a private Unix socket directory — no TCP
  listener. TLS is intentionally not compiled in for runtime revision 1;
  transport security is the OS's Unix-socket permission model. If a future
  consumer needs loopback TCP with TLS, that is a reviewed configure change
  and a runtime revision bump.
- **No credentials.** This repo bakes no roles, passwords, or `pg_hba.conf`
  policy into the runtime. Database role setup and authentication policy are
  owned by the consuming application.
- **Deterministic linkage.** Every ELF/Mach-O in the published tree is
  inspected; dependencies must be runtime-relative or on a reviewed
  per-platform system allowlist (`config/dependency-allowlist.*`). A newly
  observed dependency blocks release.
- **Third-party extensions are the exception, not the default.** Only
  PostgreSQL-supplied contrib modules are packaged by default. Any
  third-party native extension must clear the full checklist in the repo
  plan (§19): provenance, a pinned commit (verified at build time, fail
  closed on mismatch), license review, dependency audit, relocation +
  smoke tests, and update ownership — recorded in `versions.yaml`'s
  `third_party` section. One extension currently meets this bar:
  `pg_textsearch` (see `LICENSES.md`).
- **File permissions.** The packaged tree contains no world-writable
  executable or library directories (archives are normalized to uid/gid 0).

## Verifying a release

Every release asset ships with a `.sha256` checksum, a runtime manifest, an
SBOM, and a GitHub build-provenance attestation:

```sh
sha256sum -c postgres-runtime-<version>-<platform>.tar.zst.sha256
gh attestation verify postgres-runtime-<version>-<platform>.tar.zst -R <owner>/postgres-runtime
```

The consuming application must verify, at minimum: expected runtime version,
asset SHA-256, and manifest schema version.

## Reporting a vulnerability

For vulnerabilities in **PostgreSQL itself**, follow the upstream process at
<https://www.postgresql.org/support/security/> — this repository picks up
fixed patch releases through its normal reviewed upgrade flow (the
`dependency-watch` workflow surfaces them).

For issues in this repository's **packaging, pipeline, or published
artifacts** (checksum handling, linkage rewriting, workflow permissions,
artifact integrity), open a private GitHub security advisory on this
repository rather than a public issue.
