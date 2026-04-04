-- Advanced tooling for evaluation-time tuning and compact summary output.

CREATE TABLE IF NOT EXISTS semijoin_tuning_history (
  tune_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tune_ts timestamptz NOT NULL DEFAULT now(),
  rounds integer NOT NULL,
  chunk_size integer NOT NULL,
  distinct_keys integer NOT NULL,
  best_strategy text NOT NULL,
  best_avg_ms numeric(12,3) NOT NULL,
  recommended_batch_threshold integer NOT NULL,
  recommended_staged_threshold integer NOT NULL
);

DROP FUNCTION IF EXISTS autotune_semijoin_thresholds(integer, integer);
CREATE OR REPLACE FUNCTION autotune_semijoin_thresholds(
  rounds integer DEFAULT 5,
  chunk_size integer DEFAULT 500
)
RETURNS TABLE (
  distinct_keys integer,
  best_strategy text,
  best_avg_ms numeric(12,3),
  recommended_batch_threshold integer,
  recommended_staged_threshold integer,
  notes text
)
LANGUAGE plpgsql
AS $$
DECLARE
  dk integer;
  best text;
  best_ms numeric(12,3);
  batch_th integer;
  staged_th integer;
BEGIN
  IF rounds < 3 THEN
    RAISE EXCEPTION 'rounds must be >= 3';
  END IF;

  SELECT count(*)
  INTO dk
  FROM (SELECT DISTINCT a.join_key FROM a_local a) q;

  WITH runs AS (
    SELECT gs AS run_no,
           b.strategy,
           b.elapsed_ms::numeric AS elapsed_ms
    FROM generate_series(1, rounds) AS gs
    CROSS JOIN LATERAL benchmark_semijoin_strategies(chunk_size, 1500) AS b
  ), aggr AS (
    SELECT r.strategy,
           round(avg(r.elapsed_ms), 3) AS avg_ms
    FROM runs r
    GROUP BY r.strategy
  )
  SELECT a.strategy, a.avg_ms
  INTO best, best_ms
  FROM aggr a
  ORDER BY a.avg_ms ASC
  LIMIT 1;

  IF best = 'baseline_remote_scan' THEN
    batch_th := 0;
    staged_th := 0;
  ELSIF best = 'batched_any' THEN
    batch_th := dk;
    staged_th := dk;
  ELSE
    batch_th := GREATEST(dk - 1, 0);
    staged_th := dk;
  END IF;

  INSERT INTO semijoin_tuning_history (
    rounds,
    chunk_size,
    distinct_keys,
    best_strategy,
    best_avg_ms,
    recommended_batch_threshold,
    recommended_staged_threshold
  )
  VALUES (
    rounds,
    chunk_size,
    dk,
    best,
    best_ms,
    batch_th,
    staged_th
  );

  RETURN QUERY
  SELECT dk,
         best,
         best_ms,
         batch_th,
         staged_th,
         'Use these thresholds in fetch_b_semijoin_auto(batch, staged, chunk, ''auto'')';
END;
$$;
