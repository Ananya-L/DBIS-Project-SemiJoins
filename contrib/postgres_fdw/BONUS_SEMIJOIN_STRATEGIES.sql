-- Bonus semijoin strategy framework for the current demo schema.
--
-- Expected local objects:
--   customers(customer_id int, name text)
--   ft_orders(order_id int, customer_id int, amount int)
--   remote_server postgres_fdw server
--
-- Run after BONUS_SITE_B_STAGE.sql:
--
--   ~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_SEMIJOIN_STRATEGIES.sql

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

DROP FOREIGN TABLE IF EXISTS public.semijoin_keys_stage_ft;
CREATE FOREIGN TABLE public.semijoin_keys_stage_ft (
    session_id text,
    join_key integer
)
SERVER remote_server
OPTIONS (schema_name 'public', table_name 'semijoin_keys_stage');

CREATE TABLE IF NOT EXISTS public.semijoin_run_metrics (
    run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_ts timestamptz NOT NULL DEFAULT now(),
    strategy text NOT NULL,
    distinct_keys integer NOT NULL,
    key_threshold integer NOT NULL,
    chunk_size integer,
    remote_rows bigint NOT NULL,
    join_rows bigint NOT NULL,
    elapsed_ms numeric(12,3) NOT NULL
);

DROP FUNCTION IF EXISTS public.fetch_b_baseline_remote_scan(integer);
CREATE OR REPLACE FUNCTION public.fetch_b_baseline_remote_scan(
    key_threshold integer DEFAULT 1000
)
RETURNS TABLE (
    order_id integer,
    customer_id integer,
    amount integer
)
LANGUAGE sql
AS $$
    SELECT o.order_id, o.customer_id, o.amount
    FROM public.ft_orders o;
$$;

DROP FUNCTION IF EXISTS public.fetch_b_semijoin_batched_any(integer, integer);
CREATE OR REPLACE FUNCTION public.fetch_b_semijoin_batched_any(
    key_threshold integer DEFAULT 1000,
    chunk_size integer DEFAULT 500
)
RETURNS TABLE (
    order_id integer,
    customer_id integer,
    amount integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    key_batch integer[];
BEGIN
    IF chunk_size IS NULL OR chunk_size <= 0 THEN
        RAISE EXCEPTION 'chunk_size must be greater than zero';
    END IF;

    FOR key_batch IN
        WITH keys AS (
            SELECT DISTINCT c.customer_id,
                   ((row_number() OVER (ORDER BY c.customer_id) - 1) / chunk_size) AS grp
            FROM public.customers c
            WHERE c.customer_id < key_threshold
        )
        SELECT array_agg(k.customer_id ORDER BY k.customer_id)
        FROM keys k
        GROUP BY k.grp
        ORDER BY k.grp
    LOOP
        RETURN QUERY
        SELECT o.order_id, o.customer_id, o.amount
        FROM public.ft_orders o
        WHERE o.customer_id = ANY(key_batch);
    END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_b_semijoin_staged(integer);
CREATE OR REPLACE FUNCTION public.fetch_b_semijoin_staged(
    key_threshold integer DEFAULT 1000
)
RETURNS TABLE (
    order_id integer,
    customer_id integer,
    amount integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    sid text := format('%s-%s', pg_backend_pid(), clock_timestamp());
BEGIN
    INSERT INTO public.semijoin_keys_stage_ft (session_id, join_key)
    SELECT sid, c.customer_id
    FROM (
        SELECT DISTINCT c0.customer_id
        FROM public.customers c0
        WHERE c0.customer_id < key_threshold
    ) c;

    RETURN QUERY
    SELECT o.order_id, o.customer_id, o.amount
    FROM public.ft_orders o
    JOIN public.semijoin_keys_stage_ft k
      ON k.join_key = o.customer_id
     AND k.session_id = sid;

    DELETE FROM public.semijoin_keys_stage_ft
    WHERE session_id = sid;
EXCEPTION WHEN OTHERS THEN
    DELETE FROM public.semijoin_keys_stage_ft
    WHERE session_id = sid;
    RAISE;
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_b_semijoin_auto(integer, integer, integer, text);
CREATE OR REPLACE FUNCTION public.fetch_b_semijoin_auto(
    key_threshold_batch integer DEFAULT 1500,
    key_threshold_staged integer DEFAULT 50000,
    chunk_size integer DEFAULT 500,
    mode text DEFAULT 'auto'
)
RETURNS TABLE (
    strategy text,
    order_id integer,
    customer_id integer,
    amount integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM public.fetch_b_semijoin_auto_for_limit(
        1000,
        key_threshold_batch,
        key_threshold_staged,
        chunk_size,
        mode
    );
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_b_semijoin_auto_for_limit(integer, integer, integer, integer, text);
CREATE OR REPLACE FUNCTION public.fetch_b_semijoin_auto_for_limit(
    local_key_limit integer DEFAULT 1000,
    key_threshold_batch integer DEFAULT 1500,
    key_threshold_staged integer DEFAULT 50000,
    chunk_size integer DEFAULT 500,
    mode text DEFAULT 'auto'
)
RETURNS TABLE (
    strategy text,
    order_id integer,
    customer_id integer,
    amount integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    distinct_keys integer;
    chosen text;
BEGIN
    SELECT count(*)
    INTO distinct_keys
    FROM (
        SELECT DISTINCT c.customer_id
        FROM public.customers c
        WHERE c.customer_id < local_key_limit
    ) q;

    chosen := lower(coalesce(mode, 'auto'));

    IF chosen = 'auto' THEN
        IF distinct_keys <= key_threshold_batch THEN
            chosen := 'batched_any';
        ELSIF distinct_keys <= key_threshold_staged THEN
            chosen := 'staged_remote_join';
        ELSE
            chosen := 'baseline_remote_scan';
        END IF;
    END IF;

    IF chosen = 'batched_any' THEN
        RETURN QUERY
        SELECT chosen, t.order_id, t.customer_id, t.amount
        FROM public.fetch_b_semijoin_batched_any(local_key_limit, chunk_size) t;
    ELSIF chosen = 'staged_remote_join' THEN
        RETURN QUERY
        SELECT chosen, t.order_id, t.customer_id, t.amount
        FROM public.fetch_b_semijoin_staged(local_key_limit) t;
    ELSIF chosen = 'baseline_remote_scan' THEN
        RETURN QUERY
        SELECT chosen, t.order_id, t.customer_id, t.amount
        FROM public.fetch_b_baseline_remote_scan(local_key_limit) t;
    ELSE
        RAISE EXCEPTION 'mode must be auto, batched_any, staged_remote_join, or baseline_remote_scan';
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.benchmark_semijoin_strategies(integer, integer);
CREATE OR REPLACE FUNCTION public.benchmark_semijoin_strategies(
    chunk_size integer DEFAULT 500,
    key_threshold integer DEFAULT 1000
)
RETURNS TABLE (
    strategy text,
    distinct_keys integer,
    remote_rows bigint,
    join_rows bigint,
    elapsed_ms numeric(12,3)
)
LANGUAGE plpgsql
AS $$
DECLARE
    dk integer;
    t0 timestamptz;
    rr bigint;
    jr bigint;
BEGIN
    SELECT count(*)
    INTO dk
    FROM (
        SELECT DISTINCT c.customer_id
        FROM public.customers c
        WHERE c.customer_id < key_threshold
    ) q;

    t0 := clock_timestamp();
    WITH remote AS MATERIALIZED (
        SELECT *
        FROM public.fetch_b_baseline_remote_scan(key_threshold)
    ), local_customers AS MATERIALIZED (
        SELECT *
        FROM public.customers
        WHERE customer_id < key_threshold
    )
    SELECT (SELECT count(*) FROM remote),
           (SELECT count(*)
            FROM local_customers c
            JOIN remote o ON o.customer_id = c.customer_id)
    INTO rr, jr;
    RETURN QUERY
    SELECT 'baseline_remote_scan', dk, rr, jr,
           (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);

    t0 := clock_timestamp();
    WITH remote AS MATERIALIZED (
        SELECT *
        FROM public.fetch_b_semijoin_batched_any(key_threshold, chunk_size)
    ), local_customers AS MATERIALIZED (
        SELECT *
        FROM public.customers
        WHERE customer_id < key_threshold
    )
    SELECT (SELECT count(*) FROM remote),
           (SELECT count(*)
            FROM local_customers c
            JOIN remote o ON o.customer_id = c.customer_id)
    INTO rr, jr;
    RETURN QUERY
    SELECT 'batched_any', dk, rr, jr,
           (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);

    t0 := clock_timestamp();
    WITH remote AS MATERIALIZED (
        SELECT *
        FROM public.fetch_b_semijoin_staged(key_threshold)
    ), local_customers AS MATERIALIZED (
        SELECT *
        FROM public.customers
        WHERE customer_id < key_threshold
    )
    SELECT (SELECT count(*) FROM remote),
           (SELECT count(*)
            FROM local_customers c
            JOIN remote o ON o.customer_id = c.customer_id)
    INTO rr, jr;
    RETURN QUERY
    SELECT 'staged_remote_join', dk, rr, jr,
           (EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0)::numeric(12,3);
END;
$$;

DROP FUNCTION IF EXISTS public.run_and_log_benchmark(integer, integer);
CREATE OR REPLACE FUNCTION public.run_and_log_benchmark(
    chunk_size integer DEFAULT 500,
    key_threshold integer DEFAULT 1000
)
RETURNS TABLE (
    strategy text,
    distinct_keys integer,
    remote_rows bigint,
    join_rows bigint,
    elapsed_ms numeric(12,3)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH results AS (
        SELECT *
        FROM public.benchmark_semijoin_strategies(chunk_size, key_threshold)
    ), ins AS (
        INSERT INTO public.semijoin_run_metrics (
            strategy,
            distinct_keys,
            key_threshold,
            chunk_size,
            remote_rows,
            join_rows,
            elapsed_ms
        )
        SELECT r.strategy,
               r.distinct_keys,
               key_threshold,
               chunk_size,
               r.remote_rows,
               r.join_rows,
               r.elapsed_ms
        FROM results r
        RETURNING 1
    )
    SELECT r.strategy, r.distinct_keys, r.remote_rows, r.join_rows, r.elapsed_ms
    FROM results r;
END;
$$;
