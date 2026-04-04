\timing on

-- Estimate transfer volume from benchmark metrics using sampled row widths.

WITH widths AS (
  SELECT round(avg(pg_column_size(r))::numeric, 3) AS avg_b_row_bytes
  FROM (
    SELECT *
    FROM b_remote_ft
    LIMIT 1000
  ) r
), baseline AS (
  SELECT round((200000 * avg_b_row_bytes) / 1024.0 / 1024.0, 3) AS approx_baseline_mb
  FROM widths
), latest AS (
  SELECT DISTINCT ON (m.strategy)
         m.strategy,
         m.remote_rows,
         m.elapsed_ms
  FROM semijoin_run_metrics m
  ORDER BY m.strategy, m.run_id DESC
), estimates AS (
  SELECT l.strategy,
         l.remote_rows,
         l.elapsed_ms,
         w.avg_b_row_bytes,
         round((l.remote_rows * w.avg_b_row_bytes) / 1024.0 / 1024.0, 3) AS approx_transfer_mb
  FROM latest l
  CROSS JOIN widths w
)
SELECT strategy,
       remote_rows,
       avg_b_row_bytes,
       approx_transfer_mb,
       b.approx_baseline_mb,
       round((b.approx_baseline_mb - approx_transfer_mb), 3) AS approx_saved_mb,
       CASE
         WHEN b.approx_baseline_mb = 0 THEN NULL
         ELSE round(((b.approx_baseline_mb - approx_transfer_mb) / b.approx_baseline_mb) * 100.0, 2)
       END AS approx_saved_pct
FROM estimates
CROSS JOIN baseline b
ORDER BY approx_saved_mb DESC;
