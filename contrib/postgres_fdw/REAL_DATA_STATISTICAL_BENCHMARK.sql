\timing on

-- Statistical benchmark for the real customers/ft_orders data.
--
-- Why this exists:
-- A single EXPLAIN ANALYZE number can look extremely good because PostgreSQL,
-- the OS, and the remote server may have warmed caches.  We cannot fully clear
-- OS cache from SQL, so for report-quality data we do repeated measurements,
-- rotate strategy order, and report median/average/stddev instead of relying on
-- one run.
--
-- This does NOT use semijoin_run_metrics. It stores temporary measurements in
-- a temp table so repeated viva/demo runs do not pollute the main metrics log.

\echo '============================================================'
\echo 'REAL DATA STATISTICAL BENCHMARK'
\echo 'Repeated runs, rotated order, median/avg/stddev reporting'
\echo '============================================================'

DROP TABLE IF EXISTS pg_temp.semijoin_stat_runs;
CREATE TEMP TABLE semijoin_stat_runs (
    run_no integer NOT NULL,
    strategy text NOT NULL,
    key_threshold integer NOT NULL,
    chunk_size integer NOT NULL,
    remote_rows bigint NOT NULL,
    join_rows bigint NOT NULL,
    elapsed_ms numeric(12,3) NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.measure_strategy_once(
    p_strategy text,
    p_key_threshold integer,
    p_chunk_size integer
)
RETURNS TABLE (
    remote_rows bigint,
    join_rows bigint,
    elapsed_ms numeric(12,3)
)
LANGUAGE plpgsql
AS $$
DECLARE
    t0 timestamptz;
BEGIN
    -- Drop session-local plan/cache state where possible. This does not clear
    -- shared buffers or OS cache, but it reduces session-level reuse effects.
    DISCARD PLANS;

    t0 := clock_timestamp();

    IF p_strategy = 'baseline_remote_scan' THEN
        RETURN QUERY
        WITH remote AS MATERIALIZED (
            SELECT *
            FROM public.fetch_b_baseline_remote_scan(p_key_threshold)
        ), local_customers AS MATERIALIZED (
            SELECT *
            FROM public.customers
            WHERE customer_id < p_key_threshold
        )
        SELECT (SELECT count(*) FROM remote),
               (SELECT count(*)
                FROM local_customers c
                JOIN remote o ON o.customer_id = c.customer_id),
               (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);

    ELSIF p_strategy = 'batched_any' THEN
        RETURN QUERY
        WITH remote AS MATERIALIZED (
            SELECT *
            FROM public.fetch_b_semijoin_batched_any(p_key_threshold, p_chunk_size)
        ), local_customers AS MATERIALIZED (
            SELECT *
            FROM public.customers
            WHERE customer_id < p_key_threshold
        )
        SELECT (SELECT count(*) FROM remote),
               (SELECT count(*)
                FROM local_customers c
                JOIN remote o ON o.customer_id = c.customer_id),
               (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);

    ELSIF p_strategy = 'staged_remote_join' THEN
        RETURN QUERY
        WITH remote AS MATERIALIZED (
            SELECT *
            FROM public.fetch_b_semijoin_staged(p_key_threshold)
        ), local_customers AS MATERIALIZED (
            SELECT *
            FROM public.customers
            WHERE customer_id < p_key_threshold
        )
        SELECT (SELECT count(*) FROM remote),
               (SELECT count(*)
                FROM local_customers c
                JOIN remote o ON o.customer_id = c.customer_id),
               (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);
    ELSE
        RAISE EXCEPTION 'Unknown strategy: %', p_strategy;
    END IF;
END;
$$;

DO $$
DECLARE
    p_runs integer := 9;
    p_key_threshold integer := 1000;
    p_chunk_size integer := 500;
    i integer;
    s text;
    strategies text[];
    measured record;
BEGIN
    FOR i IN 1..p_runs LOOP
        -- Rotate order so the same strategy is not always first after prior
        -- queries warmed data pages.
        IF i % 3 = 1 THEN
            strategies := ARRAY['baseline_remote_scan', 'batched_any', 'staged_remote_join'];
        ELSIF i % 3 = 2 THEN
            strategies := ARRAY['batched_any', 'staged_remote_join', 'baseline_remote_scan'];
        ELSE
            strategies := ARRAY['staged_remote_join', 'baseline_remote_scan', 'batched_any'];
        END IF;

        FOREACH s IN ARRAY strategies LOOP
            SELECT *
            INTO measured
            FROM pg_temp.measure_strategy_once(s, p_key_threshold, p_chunk_size);

            INSERT INTO pg_temp.semijoin_stat_runs (
                run_no,
                strategy,
                key_threshold,
                chunk_size,
                remote_rows,
                join_rows,
                elapsed_ms
            )
            VALUES (
                i,
                s,
                p_key_threshold,
                p_chunk_size,
                measured.remote_rows,
                measured.join_rows,
                measured.elapsed_ms
            );
        END LOOP;
    END LOOP;
END;
$$;

\echo ''
\echo 'Raw repeated measurements'

SELECT *
FROM pg_temp.semijoin_stat_runs
ORDER BY run_no, strategy;

\echo ''
\echo 'Statistical summary'

SELECT strategy,
       count(*) AS runs,
       min(remote_rows) AS remote_rows,
       min(join_rows) AS join_rows,
       min(elapsed_ms) AS min_ms,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY elapsed_ms)::numeric(12,3) AS median_ms,
       avg(elapsed_ms)::numeric(12,3) AS avg_ms,
       stddev_samp(elapsed_ms)::numeric(12,3) AS stddev_ms,
       max(elapsed_ms) AS max_ms
FROM pg_temp.semijoin_stat_runs
GROUP BY strategy
ORDER BY median_ms;

\echo ''
\echo 'Correctness check across all runs'

SELECT strategy,
       bool_and(join_rows = 9990) AS expected_join_rows_ok,
       count(DISTINCT join_rows) AS distinct_join_row_counts
FROM pg_temp.semijoin_stat_runs
GROUP BY strategy
ORDER BY strategy;

