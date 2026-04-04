\timing on

-- Guardrail check: compare latest and previous elapsed_ms by strategy.
-- Fails if latest run regresses more than threshold percent.

\if :{?threshold_pct}
\else
\set threshold_pct 20
\endif

WITH ordered AS (
  SELECT m.*,
         row_number() OVER (PARTITION BY m.strategy ORDER BY m.run_id DESC) AS rn
  FROM semijoin_run_metrics m
), latest AS (
  SELECT strategy, elapsed_ms::numeric AS latest_ms
  FROM ordered
  WHERE rn = 1
), previous AS (
  SELECT strategy, elapsed_ms::numeric AS prev_ms
  FROM ordered
  WHERE rn = 2
), cmp AS (
  SELECT l.strategy,
         l.latest_ms,
         p.prev_ms,
         CASE
           WHEN p.prev_ms IS NULL OR p.prev_ms = 0 THEN NULL
           ELSE round(((l.latest_ms - p.prev_ms) / p.prev_ms) * 100.0, 3)
         END AS regression_pct
  FROM latest l
  LEFT JOIN previous p
    ON p.strategy = l.strategy
)
SELECT strategy,
       latest_ms,
       prev_ms,
       regression_pct,
       CASE
         WHEN regression_pct IS NULL THEN 'insufficient-history'
         WHEN regression_pct > :threshold_pct::numeric THEN 'regressed'
         ELSE 'ok'
       END AS guard_status
FROM cmp
ORDER BY strategy;
