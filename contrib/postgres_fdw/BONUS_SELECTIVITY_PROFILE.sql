\timing on

-- Selectivity profile for low, medium, and high key limits.
-- This compares a baseline remote scan with a pushed/batched remote filter.

DROP FUNCTION IF EXISTS public.profile_selectivity_once(integer);
CREATE OR REPLACE FUNCTION public.profile_selectivity_once(key_threshold integer)
RETURNS TABLE (
    key_limit integer,
    local_keys bigint,
    baseline_remote_rows bigint,
    baseline_join_rows bigint,
    pushed_remote_rows bigint,
    pushed_join_rows bigint,
    baseline_ms numeric(12,3),
    pushed_ms numeric(12,3)
)
LANGUAGE plpgsql
AS $$
DECLARE
    t0 timestamptz;
BEGIN
    SELECT count(DISTINCT c.customer_id)
    INTO local_keys
    FROM public.customers c
    WHERE c.customer_id < key_threshold;

    t0 := clock_timestamp();
    WITH remote AS MATERIALIZED (
        SELECT *
        FROM public.ft_orders
    ), local_customers AS MATERIALIZED (
        SELECT *
        FROM public.customers
        WHERE customer_id < key_threshold
    )
    SELECT (SELECT count(*) FROM remote),
           (SELECT count(*)
            FROM local_customers c
            JOIN remote o ON o.customer_id = c.customer_id)
    INTO baseline_remote_rows, baseline_join_rows;
    baseline_ms := (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);

    t0 := clock_timestamp();
    WITH remote AS MATERIALIZED (
        SELECT *
        FROM public.fetch_b_semijoin_batched_any(key_threshold, 500)
    ), local_customers AS MATERIALIZED (
        SELECT *
        FROM public.customers
        WHERE customer_id < key_threshold
    )
    SELECT (SELECT count(*) FROM remote),
           (SELECT count(*)
            FROM local_customers c
            JOIN remote o ON o.customer_id = c.customer_id)
    INTO pushed_remote_rows, pushed_join_rows;
    pushed_ms := (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);

    RETURN QUERY
    SELECT key_threshold,
           local_keys,
           baseline_remote_rows,
           baseline_join_rows,
           pushed_remote_rows,
           pushed_join_rows,
           baseline_ms,
           pushed_ms;
END;
$$;

WITH tiers(tier, key_threshold) AS (
    VALUES
        ('low', 100),
        ('medium', 1000),
        ('high', 5000)
)
SELECT t.tier,
       p.key_limit,
       p.local_keys,
       p.baseline_remote_rows,
       p.baseline_join_rows,
       p.pushed_remote_rows,
       p.pushed_join_rows,
       p.baseline_ms,
       p.pushed_ms,
       (p.baseline_ms - p.pushed_ms)::numeric(12,3) AS saved_ms,
       CASE
           WHEN p.pushed_ms < p.baseline_ms THEN 'semijoin_win'
           ELSE 'baseline_win'
       END AS winner
FROM tiers t
CROSS JOIN LATERAL public.profile_selectivity_once(t.key_threshold) p
ORDER BY t.key_threshold;

