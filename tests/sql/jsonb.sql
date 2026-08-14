-- JSONB (plan §9.2): containment with a GIN index, key existence, path
-- extraction, and in-place updates.
\set ON_ERROR_STOP on

CREATE TABLE events (id serial PRIMARY KEY, payload jsonb NOT NULL);
INSERT INTO events (payload)
SELECT jsonb_build_object(
  'kind', CASE WHEN g % 10 = 0 THEN 'special' ELSE 'ordinary' END,
  'seq', g,
  'tags', jsonb_build_array('t' || (g % 5)),
  'meta', jsonb_build_object('source', 'smoke', 'batch', g / 50)
)
FROM generate_series(1, 500) AS g;
CREATE INDEX events_payload_gin ON events USING gin (payload);
ANALYZE events;

-- Containment.
DO $$
BEGIN
  IF (SELECT count(*) FROM events WHERE payload @> '{"kind": "special"}') <> 50 THEN
    RAISE EXCEPTION 'jsonb containment returned wrong count';
  END IF;
  IF NOT EXISTS (SELECT FROM events WHERE payload @> '{"meta": {"source": "smoke"}}') THEN
    RAISE EXCEPTION 'nested jsonb containment failed';
  END IF;
END
$$;

-- Containment query must use the GIN index.
SET enable_seqscan = off;
DO $$
DECLARE
  plan text;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT * FROM events WHERE payload @> ''{"kind": "special"}'''
    INTO plan;
  IF plan NOT LIKE '%events_payload_gin%' THEN
    RAISE EXCEPTION 'jsonb GIN index was not used: %', plan;
  END IF;
END
$$;
RESET enable_seqscan;

-- Key existence and path extraction.
DO $$
BEGIN
  IF NOT (SELECT payload ? 'tags' FROM events WHERE id = 1) THEN
    RAISE EXCEPTION 'jsonb key-existence operator failed';
  END IF;
  IF (SELECT payload #>> '{meta,source}' FROM events WHERE id = 1) <> 'smoke' THEN
    RAISE EXCEPTION 'jsonb path extraction failed';
  END IF;
END
$$;

-- jsonb_set round-trip.
UPDATE events SET payload = jsonb_set(payload, '{meta,checked}', 'true') WHERE id = 1;
DO $$
BEGIN
  IF (SELECT payload #>> '{meta,checked}' FROM events WHERE id = 1) <> 'true' THEN
    RAISE EXCEPTION 'jsonb_set did not apply';
  END IF;
END
$$;
