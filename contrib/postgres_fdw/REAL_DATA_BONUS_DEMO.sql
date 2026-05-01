\timing on

\echo '============================================================'
\echo 'REAL DATA OVERVIEW'
\echo '============================================================'

SELECT count(*) AS local_customers,
       count(DISTINCT customer_id) AS distinct_customer_ids
FROM public.customers;

SELECT count(*) AS foreign_orders,
       count(DISTINCT customer_id) AS distinct_order_customer_ids
FROM public.ft_orders;

\echo ''
\echo '============================================================'
\echo 'C-LEVEL FDW OPTIMIZATION DEMO'
\echo 'Expected: Remote SQL contains WHERE ((customer_id < 1000))'
\echo '============================================================'

EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_id, o.amount, c.name
FROM public.ft_orders o
JOIN public.customers c
  ON o.customer_id = c.customer_id
WHERE c.customer_id < 1000;

\echo ''
\echo '============================================================'
\echo 'BONUS STRATEGY BENCHMARK: LOW SELECTIVITY CASE'
\echo 'Key condition: customer_id < 100'
\echo '============================================================'

SELECT *
FROM public.benchmark_semijoin_strategies(500, 100)
ORDER BY elapsed_ms;

\echo ''
\echo '============================================================'
\echo 'BONUS STRATEGY BENCHMARK: MEDIUM SELECTIVITY CASE'
\echo 'Key condition: customer_id < 1000'
\echo '============================================================'

SELECT *
FROM public.benchmark_semijoin_strategies(500, 1000)
ORDER BY elapsed_ms;

\echo ''
\echo '============================================================'
\echo 'BONUS STRATEGY BENCHMARK: HIGH SELECTIVITY CASE'
\echo 'Key condition: customer_id < 5000'
\echo '============================================================'

SELECT *
FROM public.benchmark_semijoin_strategies(500, 5000)
ORDER BY elapsed_ms;

\echo ''
\echo '============================================================'
\echo 'AUTO STRATEGY CHOOSER DEMO'
\echo 'Default key limit inside fetch_b_semijoin_auto is 1000'
\echo '============================================================'

WITH auto_remote AS MATERIALIZED (
    SELECT *
    FROM public.fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
)
SELECT strategy,
       count(*) AS remote_rows,
       min(customer_id) AS min_customer_id,
       max(customer_id) AS max_customer_id
FROM auto_remote
GROUP BY strategy;

\echo ''
\echo '============================================================'
\echo 'FORCED MODE COMPARISON'
\echo 'Shows that each strategy returns same row count for customer_id < 1000'
\echo '============================================================'

WITH modes(mode_name) AS (
    VALUES
        ('baseline_remote_scan'),
        ('batched_any'),
        ('staged_remote_join'),
        ('auto')
), counts AS (
    SELECT m.mode_name,
           count(*) AS remote_rows
    FROM modes m
    CROSS JOIN LATERAL public.fetch_b_semijoin_auto(1500, 50000, 500, m.mode_name) r
    GROUP BY m.mode_name
)
SELECT *
FROM counts
ORDER BY mode_name;

\echo ''
\echo '============================================================'
\echo 'CORRECTNESS CHECK'
\echo 'Baseline join count must equal auto join count'
\echo '============================================================'

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

\echo ''
\echo '============================================================'
\echo 'SELECTIVITY PROFILE'
\echo 'Shows when semijoin wins and when baseline can win'
\echo '============================================================'

\i BONUS_SELECTIVITY_PROFILE.sql

\echo ''
\echo '============================================================'
\echo 'LOGGED BENCHMARK RUN'
\echo 'Stores one medium-selectivity benchmark in semijoin_run_metrics'
\echo '============================================================'

SELECT *
FROM public.run_and_log_benchmark(500, 1000)
ORDER BY elapsed_ms;

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
LIMIT 9;

