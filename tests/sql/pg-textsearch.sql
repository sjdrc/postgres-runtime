-- pg_textsearch (third-party, plan §19): BM25 ranked full-text search via
-- a custom index access method. Requires shared_preload_libraries
-- (set server-wide by scripts/smoke-test.sh) and extensions.sql to have
-- created the extension already.
\set ON_ERROR_STOP on

CREATE TABLE bm25_docs (id bigserial PRIMARY KEY, content text);
INSERT INTO bm25_docs (content) VALUES
  ('PostgreSQL is a powerful open source database system'),
  ('BM25 is an effective ranking function for search'),
  ('Full text search with custom scoring and relevance');
INSERT INTO bm25_docs (content)
SELECT 'filler document number ' || g || ' about nothing in particular'
FROM generate_series(1, 200) AS g;

CREATE INDEX bm25_docs_idx ON bm25_docs USING bm25 (content) WITH (text_config = 'english');

DO $$
BEGIN
  IF (SELECT count(*) FROM bm25_docs) <> 203 THEN
    RAISE EXCEPTION 'bm25_docs table has unexpected row count';
  END IF;
END
$$;

-- Ranking: the document actually about "database system" must score best
-- (most negative; pg_textsearch's <@> is ASC-only, lower = better match).
DO $$
DECLARE
  best_id bigint;
BEGIN
  SELECT id INTO best_id FROM bm25_docs ORDER BY content <@> 'database system' LIMIT 1;
  IF best_id <> 1 THEN
    RAISE EXCEPTION 'BM25 ranking did not surface the expected document first (got id %)', best_id;
  END IF;
END
$$;

-- The ranked top-k query must use the BM25 index.
SET enable_seqscan = off;
DO $$
DECLARE
  plan text;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT * FROM bm25_docs ORDER BY content <@> ''database system'' LIMIT 5'
    INTO plan;
  IF plan NOT LIKE '%bm25_docs_idx%' THEN
    RAISE EXCEPTION 'BM25 index was not used: %', plan;
  END IF;
END
$$;
RESET enable_seqscan;
