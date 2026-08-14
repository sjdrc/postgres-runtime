-- LISTEN/NOTIFY (plan §9.2). psql prints every received notification as
--   Asynchronous notification "..." with payload "..." received ...
-- and the smoke-test driver asserts on that output, covering both a
-- cross-session notify (via dblink) and a same-session notify.
\set ON_ERROR_STOP on

LISTEN smoke_events;

-- Cross-session: another backend commits a NOTIFY.
SELECT dblink_connect('notifier', :'conninfo');
SELECT dblink_exec('notifier', $$NOTIFY smoke_events, 'cross-session-ping'$$);
SELECT dblink_disconnect('notifier');

-- Same-session.
SELECT pg_notify('smoke_events', 'same-session-ping');

-- Give the cross-session notification time to arrive, then run further
-- statements so psql processes and prints pending notifications.
SELECT pg_sleep(0.5);
SELECT 1 AS drain;
