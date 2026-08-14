-- FOR UPDATE SKIP LOCKED (plan §9.2), the queue-worker pattern. A second
-- session (via dblink, connected with the :'conninfo' psql variable) holds
-- a row lock while this session proves the locked row is skipped.
\set ON_ERROR_STOP on

CREATE TABLE queue (id int PRIMARY KEY, payload text NOT NULL);
INSERT INTO queue VALUES (1, 'job-one'), (2, 'job-two');

SELECT dblink_connect('locker', :'conninfo');
SELECT dblink_exec('locker', 'BEGIN');
SELECT * FROM dblink('locker', 'SELECT id FROM queue WHERE id = 1 FOR UPDATE')
  AS t (id int);

-- With row 1 locked by the other session, SKIP LOCKED must return only row 2.
DO $$
DECLARE
  got int[];
BEGIN
  SELECT array_agg(id ORDER BY id) INTO got
  FROM (SELECT id FROM queue FOR UPDATE SKIP LOCKED) s;
  IF got IS DISTINCT FROM ARRAY[2] THEN
    RAISE EXCEPTION 'FOR UPDATE SKIP LOCKED returned %, expected {2}', got;
  END IF;
END
$$;

SELECT dblink_exec('locker', 'COMMIT');

-- With the lock released, both rows are claimable again.
DO $$
DECLARE
  got int[];
BEGIN
  SELECT array_agg(id ORDER BY id) INTO got
  FROM (SELECT id FROM queue FOR UPDATE SKIP LOCKED) s;
  IF got IS DISTINCT FROM ARRAY[1, 2] THEN
    RAISE EXCEPTION 'after unlock, SKIP LOCKED returned %, expected {1,2}', got;
  END IF;
END
$$;

SELECT dblink_disconnect('locker');
