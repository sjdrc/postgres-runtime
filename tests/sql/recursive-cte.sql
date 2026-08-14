-- Recursive CTEs (plan §9.2): graph traversal, including termination on a
-- cyclic graph via UNION deduplication.
\set ON_ERROR_STOP on

CREATE TABLE edges (src int NOT NULL, dst int NOT NULL);
-- A small tree: 1 -> {2,3}, 2 -> 4, 3 -> 5, 5 -> 6 ... plus a cycle 6 -> 1.
INSERT INTO edges VALUES (1, 2), (1, 3), (2, 4), (3, 5), (5, 6), (6, 1);
-- A disconnected component that must not be reached.
INSERT INTO edges VALUES (100, 101);

-- Reachability over a cyclic graph terminates because UNION deduplicates.
DO $$
DECLARE
  reached int;
BEGIN
  WITH RECURSIVE reach (node) AS (
    SELECT 1
    UNION
    SELECT e.dst FROM edges e JOIN reach r ON e.src = r.node
  )
  SELECT count(*) INTO reached FROM reach;
  IF reached <> 6 THEN
    RAISE EXCEPTION 'recursive reachability found % nodes, expected 6', reached;
  END IF;
END
$$;

-- Depth-tracking traversal with UNION ALL on the acyclic part.
DO $$
DECLARE
  max_depth int;
BEGIN
  WITH RECURSIVE walk (node, depth) AS (
    SELECT 2, 0
    UNION ALL
    SELECT e.dst, w.depth + 1 FROM edges e JOIN walk w ON e.src = w.node
  )
  SELECT max(depth) INTO max_depth FROM walk;
  IF max_depth <> 1 THEN
    RAISE EXCEPTION 'depth traversal from node 2 reached depth %, expected 1', max_depth;
  END IF;
END
$$;

DROP TABLE edges;
