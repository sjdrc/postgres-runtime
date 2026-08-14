-- Essential checks after the runtime tree has been MOVED to a different
-- path (plan §10): the same cluster must start with the moved binaries,
-- previously written data must be intact, and every extension must still
-- resolve its shared library and support files from the new location.
\set ON_ERROR_STOP on

-- Data written before the move survived.
DO $$
BEGIN
  IF (SELECT count(*) FROM queue) <> 2 THEN
    RAISE EXCEPTION 'queue table lost rows across relocation';
  END IF;
  IF (SELECT count(*) FROM docs) <> 103 THEN
    RAISE EXCEPTION 'docs table lost rows across relocation';
  END IF;
  IF (SELECT count(*) FROM parent) <> 2 THEN
    RAISE EXCEPTION 'parent table lost rows across relocation';
  END IF;
END
$$;

-- Extension shared libraries load from the moved tree.
DO $$
BEGIN
  IF similarity('postgres', 'postgras') <= 0.3 THEN
    RAISE EXCEPTION 'pg_trgm not functional after move';
  END IF;
  IF (SELECT count(*) FROM paths WHERE p <@ 'top.a') <> 2 THEN
    RAISE EXCEPTION 'ltree not functional after move';
  END IF;
  IF unaccent('Hôtel') <> 'Hotel' THEN
    RAISE EXCEPTION 'unaccent not functional after move (tsearch_data lookup)';
  END IF;
END
$$;

-- Full-text search (share/tsearch_data + GIN) still works.
DO $$
BEGIN
  IF (SELECT count(*) FROM docs WHERE tsv @@ to_tsquery('english', 'relocation')) <> 1 THEN
    RAISE EXCEPTION 'full-text search not functional after move';
  END IF;
END
$$;

-- JSONB and new writes still work.
DO $$
BEGIN
  IF (SELECT count(*) FROM events WHERE payload @> '{"kind": "special"}') <> 50 THEN
    RAISE EXCEPTION 'jsonb containment not functional after move';
  END IF;
END
$$;
CREATE TABLE post_move_write_check (x int);
INSERT INTO post_move_write_check VALUES (1);
DROP TABLE post_move_write_check;

-- pg_stat_statements is preloaded and recording in the restarted server.
-- Reset first: query IDs are jumble-based (aliases ignored, constants
-- normalized), so without a reset the marker query would fold into an
-- existing entry that keeps its first-seen text and the LIKE would miss it.
SELECT pg_stat_statements_reset();
SELECT count(*) AS post_move_marker FROM queue;
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_stat_statements WHERE query LIKE '%post_move_marker%') < 1 THEN
    RAISE EXCEPTION 'pg_stat_statements not recording after move';
  END IF;
END
$$;
