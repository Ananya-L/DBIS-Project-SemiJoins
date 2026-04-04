\timing on

-- Summarize trend from semijoin_run_metrics and identify improving/regressing strategies.

WITH ordered AS (
  SELECT m.*,
         row_number() OVER (PARTITION BY m.strategy ORDER BY m.run_id DESC) AS rn
  FROM semijoin_run_metrics m
), latest AS (
  SELECT strategy, elapsed_ms AS latest_ms, run_id AS latest_run
  FROM ordered
  WHERE rn = 1
), previous AS (
  SELECT strategy, elapsed_ms AS prev_ms, run_id AS prev_run
  FROM ordered
  WHERE rn = 2
), delta AS (
  SELECT l.strategy,
         l.latest_run,
         p.prev_run,
         l.latest_ms,
         p.prev_ms,
         round((l.latest_ms - p.prev_ms)::numeric, 3) AS delta_ms,
         CASE
           WHEN p.prev_ms IS NULL THEN 'no_prior'
           WHEN l.latest_ms < p.prev_ms THEN 'improved'
           WHEN l.latest_ms > p.prev_ms THEN 'regressed'
           ELSE 'unchanged'
         END AS trend
  FROM latest l
  LEFT JOIN previous p
    ON p.strategy = l.strategy
)
SELECT *
FROM delta
ORDER BY latest_ms;

WITH stats AS (
  SELECT strategy,
         round(avg(elapsed_ms), 3) AS avg_ms,
         round((percentile_cont(0.95) WITHIN GROUP (ORDER BY elapsed_ms))::numeric, 3) AS p95_ms,
         round(min(elapsed_ms), 3) AS best_ms,
         round(max(elapsed_ms), 3) AS worst_ms,
         count(*) AS runs
  FROM semijoin_run_metrics
  GROUP BY strategy
)
SELECT *
FROM stats
ORDER BY avg_ms;
