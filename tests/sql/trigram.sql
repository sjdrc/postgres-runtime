-- pg_trgm (plan §9.2): similarity values and indexed fuzzy lookup.
-- Requires extensions.sql to have run first.
\set ON_ERROR_STOP on

CREATE TABLE names (id serial PRIMARY KEY, name text NOT NULL);
INSERT INTO names (name) VALUES
  ('postgres'), ('postgresql'), ('progress'), ('congress'), ('fortress');
INSERT INTO names (name)
SELECT 'unrelated-entry-' || g FROM generate_series(1, 200) AS g;

CREATE INDEX names_trgm_gin ON names USING gin (name gin_trgm_ops);
ANALYZE names;

-- similarity() returns sane values.
DO $$
BEGIN
  IF similarity('postgres', 'postgres') <> 1 THEN
    RAISE EXCEPTION 'identical strings must have similarity 1';
  END IF;
  IF similarity('postgres', 'postgras') <= 0.3 THEN
    RAISE EXCEPTION 'near-identical strings scored too low: %',
      similarity('postgres', 'postgras');
  END IF;
  IF similarity('postgres', 'zzzzzzz') >= 0.1 THEN
    RAISE EXCEPTION 'unrelated strings scored too high';
  END IF;
END
$$;

-- The % operator finds fuzzy matches.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM names WHERE name % 'postgress') THEN
    RAISE EXCEPTION 'trigram %% operator found no match for a close misspelling';
  END IF;
END
$$;

-- Fuzzy ILIKE lookup must use the trigram index.
SET enable_seqscan = off;
DO $$
DECLARE
  plan text;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT * FROM names WHERE name ILIKE ''%ostgre%'''
    INTO plan;
  IF plan NOT LIKE '%names_trgm_gin%' THEN
    RAISE EXCEPTION 'trigram GIN index was not used: %', plan;
  END IF;
END
$$;
RESET enable_seqscan;
