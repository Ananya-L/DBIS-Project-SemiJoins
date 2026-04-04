\timing on

-- Compare the latest two benchmark snapshots in semijoin_run_metrics.

WITH ordered AS (
  SELECT m.*,
         row_number() OVER (PARTITION BY m.strategy ORDER BY m.run_id DESC) AS rn
  FROM semijoin_run_metrics m
), latest AS (
  SELECT strategy,
         elapsed_ms::numeric AS latest_ms,
         remote_rows,
         join_rows
  FROM ordered
  WHERE rn = 1
), previous AS (
  SELECT strategy,
         elapsed_ms::numeric AS prev_ms
  FROM ordered
  WHERE rn = 2
), diff AS (
  SELECT l.strategy,
         l.latest_ms,
         p.prev_ms,
         round((l.latest_ms - p.prev_ms)::numeric, 3) AS delta_ms,
         CASE
           WHEN p.prev_ms IS NULL THEN 'no_previous'
           WHEN l.latest_ms < p.prev_ms THEN 'improved'
           WHEN l.latest_ms > p.prev_ms THEN 'regressed'
           ELSE 'unchanged'
         END AS trend
  FROM latest l
  LEFT JOIN previous p
    ON p.strategy = l.strategy
)
SELECT *
FROM diff
ORDER BY latest_ms;

SELECT strategy,
       round(avg(elapsed_ms), 3) AS avg_ms,
       round(min(elapsed_ms), 3) AS best_ms,
       round(max(elapsed_ms), 3) AS worst_ms,
       count(*) AS runs
FROM semijoin_run_metrics
GROUP BY strategy
ORDER BY avg_ms;
