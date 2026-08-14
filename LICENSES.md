# Licenses and notices

This repository's build recipe packages the following third-party software
into the published runtime artifacts.

## PostgreSQL

The runtime is built from unmodified official PostgreSQL sources and is
distributed under the [PostgreSQL License](https://www.postgresql.org/about/licence/):

> Portions Copyright © 1996-2026, The PostgreSQL Global Development Group
>
> Portions Copyright © 1994, The Regents of the University of California
>
> Permission to use, copy, modify, and distribute this software and its
> documentation for any purpose, without fee, and without a written
> agreement is hereby granted, provided that the above copyright notice and
> this paragraph and the following two paragraphs appear in all copies.
>
> IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
> DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES,
> INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS
> DOCUMENTATION, EVEN IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF
> THE POSSIBILITY OF SUCH DAMAGE.
>
> THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
> INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
> AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS
> ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATIONS
> TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

This covers the server, client tools, and all packaged contrib extensions
(`pg_trgm`, `pg_stat_statements`, `ltree`, `unaccent`, `dblink`, and the
rest of the supplied contrib set), as well as the compiled-in IANA timezone
data (public domain).

## Bundled shared libraries

The Linux artifacts bundle these non-system libraries in `lib/`
(see `config/bundled-libs.linux`); macOS artifacts bundle the subset in
`config/bundled-libs.darwin`:

| Library | License | Notes |
| --- | --- | --- |
| zlib (`libz`) | [zlib License](https://zlib.net/zlib_license.html) | compression (pg_dump, TOAST) |
| LZ4 (`liblz4`) | [BSD-2-Clause](https://github.com/lz4/lz4/blob/dev/lib/LICENSE) (library) | WAL/TOAST/backup compression |
| Zstandard (`libzstd`) | [BSD-3-Clause](https://github.com/facebook/zstd/blob/dev/LICENSE) | backup/archive compression |

Exact per-file SHA-256 digests for the bundled libraries are recorded in
each artifact's CycloneDX SBOM (`*.sbom.cdx.json`).

System libraries (glibc and the dynamic loader on Linux; `libSystem` and
other `/usr/lib`//`/System/Library` libraries on macOS) are **not**
redistributed — the runtime links against the host's copies, restricted by
the reviewed allowlists in `config/dependency-allowlist.*`.
