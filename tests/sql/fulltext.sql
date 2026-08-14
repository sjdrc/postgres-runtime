-- Full-text search (plan §9.2): tsvector/tsquery with an explicit english
-- configuration (locale-independent), stored generated tsvector column,
-- GIN index usage, and ranking. Row counts are deterministic because
-- post-move.sql re-asserts them after relocation.
\set ON_ERROR_STOP on

CREATE TABLE docs (
  id serial PRIMARY KEY,
  body text NOT NULL,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', body)) STORED
);

INSERT INTO docs (body) VALUES
  ('postgres runtime relocation proof document'),
  ('full text search with ranking and indexes'),
  ('the quick brown fox jumps over the lazy dog');
INSERT INTO docs (body)
SELECT 'filler document number ' || g || ' about nothing in particular'
FROM generate_series(1, 100) AS g;

CREATE INDEX docs_tsv_gin ON docs USING gin (tsv);
ANALYZE docs;

DO $$
BEGIN
  IF (SELECT count(*) FROM docs) <> 103 THEN
    RAISE EXCEPTION 'docs table has unexpected row count';
  END IF;
  IF (SELECT count(*) FROM docs WHERE tsv @@ to_tsquery('english', 'postgres & runtime')) <> 1 THEN
    RAISE EXCEPTION 'tsquery match returned wrong count';
  END IF;
  IF (SELECT count(*) FROM docs WHERE tsv @@ websearch_to_tsquery('english', 'quick fox')) <> 1 THEN
    RAISE EXCEPTION 'websearch_to_tsquery match returned wrong count';
  END IF;
  -- Stemming: "indexes" must match "index" queries.
  IF (SELECT count(*) FROM docs WHERE tsv @@ to_tsquery('english', 'index')) <> 1 THEN
    RAISE EXCEPTION 'english stemming did not match';
  END IF;
END
$$;

-- The search must use the GIN index.
SET enable_seqscan = off;
DO $$
DECLARE
  plan text;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT id FROM docs WHERE tsv @@ to_tsquery(''english'', ''relocation'')'
    INTO plan;
  IF plan NOT LIKE '%docs_tsv_gin%' THEN
    RAISE EXCEPTION 'full-text GIN index was not used: %', plan;
  END IF;
END
$$;
RESET enable_seqscan;

-- Ranking produces a positive score for a matching document.
DO $$
BEGIN
  IF (SELECT ts_rank(tsv, to_tsquery('english', 'relocation')) FROM docs WHERE id = 1) <= 0 THEN
    RAISE EXCEPTION 'ts_rank returned a non-positive score for a match';
  END IF;
END
$$;
