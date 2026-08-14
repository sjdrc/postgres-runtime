-- Advisory locks (plan §9.2): both session-level and transaction-level,
-- with real contention from a second session via dblink.
\set ON_ERROR_STOP on

SELECT dblink_connect('advlock', :'conninfo');

-- Session-level: the other session holds the lock, so try-lock here fails.
SELECT * FROM dblink('advlock', 'SELECT pg_advisory_lock(781215)') AS t (r text);
DO $$
BEGIN
  IF pg_try_advisory_lock(781215) THEN
    RAISE EXCEPTION 'acquired a session advisory lock held by another session';
  END IF;
END
$$;

-- After the other session releases it, acquisition succeeds.
SELECT * FROM dblink('advlock', 'SELECT pg_advisory_unlock(781215)') AS t (r boolean);
DO $$
BEGIN
  IF NOT pg_try_advisory_lock(781215) THEN
    RAISE EXCEPTION 'could not acquire a released session advisory lock';
  END IF;
  IF NOT pg_advisory_unlock(781215) THEN
    RAISE EXCEPTION 'could not release our own session advisory lock';
  END IF;
END
$$;

-- Transaction-level: held for the duration of the other session's
-- transaction, then automatically released by its COMMIT.
SELECT dblink_exec('advlock', 'BEGIN');
SELECT * FROM dblink('advlock', 'SELECT pg_advisory_xact_lock(781216)') AS t (r text);
DO $$
BEGIN
  IF pg_try_advisory_xact_lock(781216) THEN
    RAISE EXCEPTION 'acquired a xact advisory lock held by another transaction';
  END IF;
END
$$;
SELECT dblink_exec('advlock', 'COMMIT');
DO $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(781216) THEN
    RAISE EXCEPTION 'xact advisory lock was not released by remote COMMIT';
  END IF;
END
$$;

SELECT dblink_disconnect('advlock');
