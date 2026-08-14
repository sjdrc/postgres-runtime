# Patch policy

This directory is **normally empty** (only this README). PostgreSQL is not
forked and not modified: releases are built from the official, checksum-pinned
source tarball exactly as published.

CI enforces this via `scripts/check-patch-policy.sh`, which fails if any file
other than this README exists here.

## If a patch ever becomes genuinely necessary

A patch is a last resort for a concrete build blocker or critical defect that
cannot wait for an upstream release. Every patch added here MUST come with:

1. **An explanation** — what breaks without it, and why it cannot be solved in
   packaging instead.
2. **An upstream reference** — the mailing-list thread, commitfest entry, or
   upstream commit it backports, where applicable.
3. **A proving test** — a test in `tests/` that fails without the patch and
   passes with it.
4. **An expiry condition** — the upstream release (or event) that makes the
   patch removable, checked at every version bump.
5. **Manifest inclusion** — the release manifest must record that the source
   was patched.

The change adding a patch must also update `scripts/check-patch-policy.sh` to
validate the above, so the policy stays machine-enforced. If a patch stack
ever becomes long-lived, move it to a small maintained fork and keep this
packaging repository unchanged (plan §1.1).
