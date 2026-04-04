\timing on

-- Compute confidence intervals for strategy runtimes over repeated benchmark runs.

\if :{?rounds}
\else
\set rounds 7
\endif

\if :{?chunk_size}
\else
\set chunk_size 500
\endif

WITH runs AS (
  SELECT gs AS run_no,
         b.strategy,
         b.elapsed_ms::numeric AS elapsed_ms,
         b.remote_rows,
         b.join_rows
  FROM generate_series(1, :rounds::int) AS gs
  CROSS JOIN LATERAL benchmark_semijoin_strategies(:chunk_size::int, 1500) AS b
), stats AS (
  SELECT strategy,
         count(*) AS samples,
         round(avg(elapsed_ms), 3) AS mean_ms,
         round(stddev_samp(elapsed_ms), 3) AS stddev_ms,
         round(min(elapsed_ms), 3) AS min_ms,
         round(max(elapsed_ms), 3) AS max_ms,
         round((avg(elapsed_ms) - 1.96 * (stddev_samp(elapsed_ms) / sqrt(count(*))))::numeric, 3) AS ci95_low,
         round((avg(elapsed_ms) + 1.96 * (stddev_samp(elapsed_ms) / sqrt(count(*))))::numeric, 3) AS ci95_high,
         round(avg(remote_rows::numeric), 3) AS avg_remote_rows,
         round(avg(join_rows::numeric), 3) AS avg_join_rows
  FROM runs
  GROUP BY strategy
)
SELECT *
FROM stats
ORDER BY mean_ms;
