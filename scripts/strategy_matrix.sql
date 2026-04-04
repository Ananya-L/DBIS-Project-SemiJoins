\timing on

-- Evaluate multiple chunk sizes and summarize the best strategy per chunk.

WITH chunk_cfg AS (
  SELECT unnest(ARRAY[100, 200, 500, 1000, 2000]) AS chunk_size
), runs AS (
  SELECT c.chunk_size,
         b.strategy,
         b.distinct_keys,
         b.remote_rows,
         b.join_rows,
         b.elapsed_ms::numeric AS elapsed_ms
  FROM chunk_cfg c
  CROSS JOIN LATERAL benchmark_semijoin_strategies(c.chunk_size, 1500) AS b
), ranked AS (
  SELECT r.*,
         row_number() OVER (PARTITION BY r.chunk_size ORDER BY r.elapsed_ms ASC) AS rn
  FROM runs r
)
SELECT r.chunk_size,
       r.strategy,
       r.distinct_keys,
       r.remote_rows,
       r.join_rows,
       round(r.elapsed_ms, 3) AS elapsed_ms,
       CASE WHEN r.rn = 1 THEN 'winner' ELSE '' END AS label
FROM ranked r
ORDER BY r.chunk_size, r.elapsed_ms;

WITH chunk_cfg AS (
  SELECT unnest(ARRAY[100, 200, 500, 1000, 2000]) AS chunk_size
), runs AS (
  SELECT c.chunk_size,
         b.strategy,
         b.elapsed_ms::numeric AS elapsed_ms
  FROM chunk_cfg c
  CROSS JOIN LATERAL benchmark_semijoin_strategies(c.chunk_size, 1500) AS b
), winners AS (
  SELECT r.chunk_size,
         (SELECT strategy
          FROM runs r2
          WHERE r2.chunk_size = r.chunk_size
          ORDER BY r2.elapsed_ms ASC
          LIMIT 1) AS best_strategy,
         (SELECT round(elapsed_ms, 3)
          FROM runs r2
          WHERE r2.chunk_size = r.chunk_size
          ORDER BY r2.elapsed_ms ASC
          LIMIT 1) AS best_ms
  FROM runs r
  GROUP BY r.chunk_size
)
SELECT *
FROM winners
ORDER BY chunk_size;
