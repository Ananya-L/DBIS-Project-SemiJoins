\timing on

-- 1. Compare all strategies and save the run to semijoin_run_metrics.
SELECT *
FROM public.run_and_log_benchmark(500, 1000)
ORDER BY elapsed_ms;

-- 2. Show adaptive strategy selection.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
WITH auto_remote AS MATERIALIZED (
    SELECT *
    FROM public.fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
)
SELECT strategy, count(*) AS remote_rows
FROM auto_remote
GROUP BY strategy;

-- 3. Correctness check: baseline and auto must produce the same join row count.
WITH baseline AS (
    SELECT c.customer_id, o.order_id
    FROM public.customers c
    JOIN public.ft_orders o
      ON o.customer_id = c.customer_id
    WHERE c.customer_id < 1000
), auto_join AS (
    WITH auto_remote AS MATERIALIZED (
        SELECT order_id, customer_id
        FROM public.fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
    )
    SELECT c.customer_id, r.order_id
    FROM public.customers c
    JOIN auto_remote r
      ON r.customer_id = c.customer_id
    WHERE c.customer_id < 1000
)
SELECT (SELECT count(*) FROM baseline) AS baseline_rows,
       (SELECT count(*) FROM auto_join) AS auto_rows,
       ((SELECT count(*) FROM baseline) = (SELECT count(*) FROM auto_join)) AS rowcount_equal;

-- 4. Show recent experiment history.
SELECT run_id,
       run_ts,
       strategy,
       distinct_keys,
       key_threshold,
       chunk_size,
       remote_rows,
       join_rows,
       elapsed_ms
FROM public.semijoin_run_metrics
ORDER BY run_id DESC
LIMIT 12;

