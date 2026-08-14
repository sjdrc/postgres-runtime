-- Core relational features (plan §9.1): transactions, foreign keys,
-- generated columns, partial + partial-unique indexes, GiST, COPY.
\set ON_ERROR_STOP on

BEGIN;
CREATE TABLE parent (id int PRIMARY KEY, name text NOT NULL);
CREATE TABLE child (
  id int PRIMARY KEY,
  parent_id int NOT NULL REFERENCES parent (id) ON DELETE CASCADE,
  qty int NOT NULL DEFAULT 0,
  doubled int GENERATED ALWAYS AS (qty * 2) STORED
);
INSERT INTO parent VALUES (1, 'a'), (2, 'b'), (3, 'c');
INSERT INTO child (id, parent_id, qty) VALUES (10, 1, 5), (11, 2, 7), (12, 3, 9);
COMMIT;

-- Foreign keys are enforced and the failure rolls back cleanly.
DO $$
BEGIN
  BEGIN
    INSERT INTO child (id, parent_id, qty) VALUES (99, 999, 1);
    RAISE EXCEPTION 'foreign key was not enforced';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;
END
$$;

-- Generated columns compute correctly.
DO $$
BEGIN
  IF (SELECT doubled FROM child WHERE id = 10) <> 10 THEN
    RAISE EXCEPTION 'generated column returned wrong value';
  END IF;
END
$$;

-- ON DELETE CASCADE.
DELETE FROM parent WHERE id = 3;
DO $$
BEGIN
  IF EXISTS (SELECT FROM child WHERE parent_id = 3) THEN
    RAISE EXCEPTION 'ON DELETE CASCADE did not remove child rows';
  END IF;
END
$$;

-- Explicit rollback works.
BEGIN;
INSERT INTO parent VALUES (100, 'rollback-me');
ROLLBACK;
DO $$
BEGIN
  IF EXISTS (SELECT FROM parent WHERE id = 100) THEN
    RAISE EXCEPTION 'ROLLBACK did not undo the insert';
  END IF;
END
$$;

-- Partial unique index: uniqueness only among 'active' rows.
CREATE TABLE tasks (id serial PRIMARY KEY, state text NOT NULL, key text NOT NULL);
CREATE UNIQUE INDEX tasks_active_key ON tasks (key) WHERE state = 'active';
INSERT INTO tasks (state, key) VALUES ('active', 'k1'), ('done', 'k1'), ('done', 'k1');
DO $$
BEGIN
  BEGIN
    INSERT INTO tasks (state, key) VALUES ('active', 'k1');
    RAISE EXCEPTION 'partial unique index was not enforced';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END
$$;

-- GiST: range overlap query must use the index.
CREATE TABLE reservations (id int, during tsrange);
CREATE INDEX reservations_during_gist ON reservations USING gist (during);
INSERT INTO reservations
SELECT g,
  tsrange(timestamp '2026-01-01 00:00' + g * interval '1 hour',
          timestamp '2026-01-01 00:00' + (g + 2) * interval '1 hour')
FROM generate_series(1, 300) AS g;
ANALYZE reservations;

SET enable_seqscan = off;
DO $$
DECLARE
  plan text;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT * FROM reservations
           WHERE during && tsrange(''2026-01-01 05:00'', ''2026-01-01 06:00'')'
    INTO plan;
  IF plan NOT LIKE '%reservations_during_gist%' THEN
    RAISE EXCEPTION 'GiST index was not used: %', plan;
  END IF;
END
$$;
RESET enable_seqscan;

-- COPY in both directions.
CREATE TABLE copy_t (a int, b text);
COPY copy_t FROM stdin;
1	one
2	two
3	three
\.
DO $$
BEGIN
  IF (SELECT count(*) FROM copy_t) <> 3 THEN
    RAISE EXCEPTION 'COPY FROM stdin loaded wrong row count';
  END IF;
END
$$;
COPY (SELECT * FROM copy_t ORDER BY a) TO stdout;
DROP TABLE copy_t;
