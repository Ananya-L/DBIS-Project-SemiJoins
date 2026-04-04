\timing on

-- 1) Strategy comparison and logging.
SELECT *
FROM run_and_log_benchmark(500, 1500)
ORDER BY elapsed_ms;

-- 2) Auto strategy chooser demo.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
WITH auto_remote AS MATERIALIZED (
  SELECT *
  FROM fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
)
SELECT strategy, count(*) AS remote_rows
FROM auto_remote
GROUP BY strategy;

-- 3) Correctness check against baseline.
WITH baseline AS (
  SELECT a.id AS a_id, b.id AS b_id
  FROM a_local a
  JOIN b_remote_ft b
    ON b.join_key = a.join_key
), auto_join AS (
  WITH auto_remote AS MATERIALIZED (
    SELECT id, join_key
    FROM fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
  )
  SELECT a.id AS a_id, r.id AS b_id
  FROM a_local a
  JOIN auto_remote r
    ON r.join_key = a.join_key
)
SELECT
  (SELECT count(*) FROM baseline) AS baseline_rows,
  (SELECT count(*) FROM auto_join) AS auto_rows,
  ((SELECT count(*) FROM baseline) = (SELECT count(*) FROM auto_join)) AS rowcount_equal;

-- 4) Historical metrics table.
SELECT run_id, run_ts, strategy, distinct_keys, chunk_size, remote_rows, join_rows, elapsed_ms
FROM semijoin_run_metrics
ORDER BY run_id DESC
LIMIT 12;
