\timing on

-- Runs multiple rounds and reports avg/p95/stddev to avoid one-off timing noise.
-- Uses existing benchmark_semijoin_strategies() function on Site A.

DROP FUNCTION IF EXISTS run_statistical_benchmark(integer, integer);
CREATE OR REPLACE FUNCTION run_statistical_benchmark(
  rounds integer DEFAULT 5,
  chunk_size integer DEFAULT 500
)
RETURNS TABLE (
  strategy text,
  rounds_run integer,
  avg_ms numeric(12,3),
  p95_ms numeric(12,3),
  stddev_ms numeric(12,3),
  min_ms numeric(12,3),
  max_ms numeric(12,3),
  avg_remote_rows numeric(18,3),
  avg_join_rows numeric(18,3)
)
LANGUAGE plpgsql
AS $$
BEGIN
  IF rounds IS NULL OR rounds < 3 THEN
    RAISE EXCEPTION 'rounds must be >= 3 for meaningful statistics';
  END IF;

  RETURN QUERY
  WITH runs AS (
    SELECT gs AS run_no,
           b.strategy,
           b.remote_rows,
           b.join_rows,
           b.elapsed_ms::numeric AS elapsed_ms
    FROM generate_series(1, rounds) AS gs
    CROSS JOIN LATERAL benchmark_semijoin_strategies(chunk_size, 1500) AS b
  )
  SELECT r.strategy,
         count(*)::integer AS rounds_run,
         round(avg(r.elapsed_ms), 3) AS avg_ms,
      round((percentile_cont(0.95) WITHIN GROUP (ORDER BY r.elapsed_ms))::numeric, 3) AS p95_ms,
         round(coalesce(stddev_samp(r.elapsed_ms), 0), 3) AS stddev_ms,
         round(min(r.elapsed_ms), 3) AS min_ms,
         round(max(r.elapsed_ms), 3) AS max_ms,
         round(avg(r.remote_rows::numeric), 3) AS avg_remote_rows,
         round(avg(r.join_rows::numeric), 3) AS avg_join_rows
  FROM runs r
  GROUP BY r.strategy
  ORDER BY avg_ms ASC;
END;
$$;

SELECT *
FROM run_statistical_benchmark(5, 500);
