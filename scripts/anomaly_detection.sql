\timing on

-- Detect outlier runs in semijoin_run_metrics using z-score per strategy.

WITH stats AS (
  SELECT strategy,
         avg(elapsed_ms::numeric) AS mean_ms,
         stddev_samp(elapsed_ms::numeric) AS std_ms
  FROM semijoin_run_metrics
  GROUP BY strategy
), zcalc AS (
  SELECT m.run_id,
         m.run_ts,
         m.strategy,
         m.elapsed_ms,
         s.mean_ms,
         coalesce(s.std_ms, 0) AS std_ms,
         CASE
           WHEN coalesce(s.std_ms, 0) = 0 THEN 0
           ELSE round(((m.elapsed_ms::numeric - s.mean_ms) / s.std_ms), 3)
         END AS z_score
  FROM semijoin_run_metrics m
  JOIN stats s
    ON s.strategy = m.strategy
)
SELECT run_id,
       run_ts,
       strategy,
       elapsed_ms,
       round(mean_ms, 3) AS mean_ms,
       round(std_ms, 3) AS std_ms,
       z_score,
       CASE
         WHEN abs(z_score) >= 2.0 THEN 'outlier'
         ELSE 'normal'
       END AS status
FROM zcalc
ORDER BY run_id DESC
LIMIT 50;
