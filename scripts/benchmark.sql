\timing on

-- Baseline: direct join to foreign table.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF, BUFFERS)
SELECT count(*)
FROM a_local a
JOIN b_remote_ft b
  ON b.join_key = a.join_key;

-- Semijoin path: fetch only needed keys first, then join locally.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF, BUFFERS)
WITH b_needed AS MATERIALIZED (
  SELECT *
  FROM fetch_b_semijoin(500)
)
SELECT count(*)
FROM a_local a
JOIN b_needed b
  ON b.join_key = a.join_key;

-- Result correctness check.
WITH baseline AS (
  SELECT a.id AS a_id, b.id AS b_id
  FROM a_local a
  JOIN b_remote_ft b
    ON b.join_key = a.join_key
), semijoined AS (
  WITH b_needed AS MATERIALIZED (
    SELECT *
    FROM fetch_b_semijoin(500)
  )
  SELECT a.id AS a_id, b.id AS b_id
  FROM a_local a
  JOIN b_needed b
    ON b.join_key = a.join_key
)
SELECT
  (SELECT count(*) FROM baseline) AS baseline_rows,
  (SELECT count(*) FROM semijoined) AS semijoin_rows,
  ((SELECT count(*) FROM baseline) = (SELECT count(*) FROM semijoined)) AS rowcount_equal;
