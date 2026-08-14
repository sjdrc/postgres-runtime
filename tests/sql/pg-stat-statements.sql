-- pg_stat_statements (plan §9.3): the server is started with the library
-- preloaded (see scripts/smoke-test.sh); prove that statistics are
-- actually recorded for representative queries.
\set ON_ERROR_STOP on

SELECT pg_stat_statements_reset();

-- Representative workload.
SELECT sum(g) AS marker_sum_workload FROM generate_series(1, 10000) AS g;
SELECT count(*) FROM queue WHERE payload LIKE 'job%';
SELECT count(*) FROM docs WHERE tsv @@ to_tsquery('english', 'relocation');

DO $$
DECLARE
  n bigint;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_statements
  WHERE query LIKE '%marker_sum_workload%';
  IF n < 1 THEN
    RAISE EXCEPTION 'pg_stat_statements did not record the workload query';
  END IF;
  SELECT calls INTO n FROM pg_stat_statements
  WHERE query LIKE '%marker_sum_workload%' LIMIT 1;
  IF n < 1 THEN
    RAISE EXCEPTION 'pg_stat_statements recorded zero calls';
  END IF;
  IF (SELECT count(*) FROM pg_stat_statements) < 3 THEN
    RAISE EXCEPTION 'pg_stat_statements recorded suspiciously few statements';
  END IF;
END
$$;
