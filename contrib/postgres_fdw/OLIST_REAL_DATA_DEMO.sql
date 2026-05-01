\timing on

\echo '============================================================'
\echo 'OLIST REAL ANONYMIZED E-COMMERCE DATA DEMO'
\echo '============================================================'

SELECT count(*) AS local_olist_customers,
       count(DISTINCT customer_key) AS distinct_customer_keys,
       count(DISTINCT customer_state) AS states
FROM public.olist_customers_local;

SELECT count(*) AS remote_olist_orders,
       count(DISTINCT customer_key) AS distinct_order_customer_keys,
       sum(amount) AS total_order_amount
FROM public.ft_olist_orders;

\echo ''
\echo 'Top customer states in local Olist data'

SELECT customer_state,
       count(*) AS customers
FROM public.olist_customers_local
GROUP BY customer_state
ORDER BY customers DESC
LIMIT 10;

\echo ''
\echo '============================================================'
\echo 'MAIN FDW OPTIMIZATION ON REAL OLIST DATA'
\echo 'Join local real customers to foreign real orders'
\echo '============================================================'

EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_key,
       o.amount,
       c.customer_city,
       c.customer_state
FROM public.ft_olist_orders o
JOIN public.olist_customers_local c
  ON o.customer_key = c.customer_key
WHERE c.customer_key < 1000;

\echo ''
\echo '============================================================'
\echo 'REAL-DATA BUSINESS QUERY'
\echo 'Order value by state for the first 1000 customer keys'
\echo '============================================================'

SELECT c.customer_state,
       count(*) AS orders,
       sum(o.amount) AS total_amount,
       round(avg(o.amount)::numeric, 2) AS avg_amount
FROM public.ft_olist_orders o
JOIN public.olist_customers_local c
  ON o.customer_key = c.customer_key
WHERE c.customer_key < 1000
GROUP BY c.customer_state
ORDER BY total_amount DESC
LIMIT 10;

\echo ''
\echo '============================================================'
\echo 'LOW/MEDIUM/HIGH REAL OLIST SELECTIVITY'
\echo '============================================================'

WITH cases(label, key_limit) AS (
    VALUES
        ('low', 100),
        ('medium', 1000),
        ('high', 5000)
)
SELECT label,
       key_limit,
       (SELECT count(*) FROM public.olist_customers_local c WHERE c.customer_key < cases.key_limit) AS local_customers,
       (SELECT count(*) FROM public.ft_olist_orders o) AS baseline_remote_rows,
       (SELECT count(*) FROM public.ft_olist_orders o WHERE o.customer_key < cases.key_limit) AS pushed_remote_rows
FROM cases;

