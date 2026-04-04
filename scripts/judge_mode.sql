\timing off
\pset tuples_only on
\pset format aligned

WITH runs AS (
  SELECT gs AS run_no,
         b.strategy,
         b.elapsed_ms::numeric AS elapsed_ms,
         b.remote_rows,
         b.join_rows
  FROM generate_series(1, 3) AS gs
  CROSS JOIN LATERAL benchmark_semijoin_strategies(500, 1500) AS b
), aggr AS (
  SELECT strategy,
         round(avg(elapsed_ms), 3) AS avg_ms,
         round((percentile_cont(0.95) WITHIN GROUP (ORDER BY elapsed_ms))::numeric, 3) AS p95_ms,
         round(avg(remote_rows::numeric), 0) AS avg_remote_rows,
         round(avg(join_rows::numeric), 0) AS avg_join_rows
  FROM runs
  GROUP BY strategy
), best AS (
  SELECT strategy, avg_ms
  FROM aggr
  ORDER BY avg_ms ASC
  LIMIT 1
), correctness AS (
  WITH baseline AS (
    SELECT a.id AS a_id, b.id AS b_id
    FROM a_local a
    JOIN b_remote_ft b ON b.join_key = a.join_key
  ), auto_join AS (
    WITH remote_auto AS MATERIALIZED (
      SELECT id, join_key
      FROM fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
    )
    SELECT a.id AS a_id, r.id AS b_id
    FROM a_local a
    JOIN remote_auto r ON r.join_key = a.join_key
  )
  SELECT ((SELECT count(*) FROM baseline) = (SELECT count(*) FROM auto_join)) AS pass
)
SELECT 'RESULT' AS label,
       CASE WHEN c.pass THEN 'PASS' ELSE 'FAIL' END AS correctness,
       b.strategy AS fastest_strategy,
       b.avg_ms AS fastest_avg_ms
FROM correctness c
CROSS JOIN best b;

WITH runs AS (
  SELECT gs AS run_no,
         b.strategy,
         b.elapsed_ms::numeric AS elapsed_ms,
         b.remote_rows,
         b.join_rows
  FROM generate_series(1, 3) AS gs
  CROSS JOIN LATERAL benchmark_semijoin_strategies(500, 1500) AS b
), aggr AS (
  SELECT strategy,
         round(avg(elapsed_ms), 3) AS avg_ms,
         round((percentile_cont(0.95) WITHIN GROUP (ORDER BY elapsed_ms))::numeric, 3) AS p95_ms,
         round(avg(remote_rows::numeric), 0) AS avg_remote_rows,
         round(avg(join_rows::numeric), 0) AS avg_join_rows
  FROM runs
  GROUP BY strategy
)
SELECT strategy,
       avg_ms,
       p95_ms,
       avg_remote_rows,
       avg_join_rows
FROM aggr
ORDER BY avg_ms;
