-- Extension installation (plan §6). Runs first: later test files depend on
-- the extensions created here. dblink is installed purely as test
-- infrastructure for the multi-session tests (skip-locked, advisory-lock,
-- listen-notify); it ships in the runtime because all supplied contrib
-- modules are packaged.
\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS ltree;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS dblink;

-- ltree: functional check with a GiST index (path containment).
CREATE TABLE paths (p ltree);
INSERT INTO paths VALUES ('top'), ('top.a'), ('top.a.x'), ('top.b');
CREATE INDEX paths_gist ON paths USING gist (p);

DO $$
BEGIN
  IF (SELECT count(*) FROM paths WHERE p <@ 'top.a') <> 2 THEN
    RAISE EXCEPTION 'ltree containment query returned wrong result';
  END IF;
  IF nlevel('top.a.x'::ltree) <> 3 THEN
    RAISE EXCEPTION 'ltree nlevel() returned wrong result';
  END IF;
END
$$;

-- unaccent: requires its dictionary file from share/tsearch_data.
DO $$
BEGIN
  IF unaccent('Hôtel Café') <> 'Hotel Cafe' THEN
    RAISE EXCEPTION 'unaccent() returned wrong result: %', unaccent('Hôtel Café');
  END IF;
END
$$;
