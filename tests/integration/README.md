# Integration tests

Placeholder for future runtime-level integration tests that go beyond the
SQL smoke suite in `tests/sql/` (for example, exercising the runtime through
`fergusstrange/embedded-postgres` the way the main application does).

Main-application consumption logic itself does **not** belong in this
repository (plan §22, milestone 5) — it lives in the main Go repo, which
pins a published runtime release and runs its own end-to-end suite.
