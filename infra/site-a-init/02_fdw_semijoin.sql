CREATE EXTENSION IF NOT EXISTS postgres_fdw;

DROP SERVER IF EXISTS site_b CASCADE;
CREATE SERVER site_b
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'site_b', dbname 'site_b_db', port '5432');

CREATE USER MAPPING FOR CURRENT_USER
  SERVER site_b
  OPTIONS (user 'postgres', password 'postgres');

DROP FOREIGN TABLE IF EXISTS b_remote_ft;
CREATE FOREIGN TABLE b_remote_ft (
  id bigint,
  join_key int,
  payload text,
  updated_at timestamptz
)
SERVER site_b
OPTIONS (schema_name 'public', table_name 'b_remote');

DROP FOREIGN TABLE IF EXISTS semijoin_keys_stage_ft;
CREATE FOREIGN TABLE semijoin_keys_stage_ft (
  session_id text,
  join_key int
)
SERVER site_b
OPTIONS (schema_name 'public', table_name 'semijoin_keys_stage');

DROP FUNCTION IF EXISTS fetch_b_semijoin(integer);
CREATE OR REPLACE FUNCTION fetch_b_semijoin(chunk_size integer DEFAULT 1000)
RETURNS TABLE (
  id bigint,
  join_key int,
  payload text,
  updated_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
  key_batch int[];
BEGIN
  IF chunk_size IS NULL OR chunk_size <= 0 THEN
    RAISE EXCEPTION 'chunk_size must be > 0';
  END IF;

  FOR key_batch IN
    WITH keys AS (
      SELECT DISTINCT a.join_key,
             ((row_number() OVER (ORDER BY a.join_key) - 1) / chunk_size) AS grp
      FROM a_local a
    )
    SELECT array_agg(keys.join_key ORDER BY keys.join_key)
    FROM keys
    GROUP BY grp
    ORDER BY grp
  LOOP
    RETURN QUERY
    SELECT b.id, b.join_key, b.payload, b.updated_at
    FROM b_remote_ft b
    WHERE b.join_key = ANY(key_batch);
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS fetch_b_semijoin_staged();
CREATE OR REPLACE FUNCTION fetch_b_semijoin_staged()
RETURNS TABLE (
  id bigint,
  join_key int,
  payload text,
  updated_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
  sid text := format('%s-%s', txid_current()::text, clock_timestamp()::text);
BEGIN
  INSERT INTO semijoin_keys_stage_ft (session_id, join_key)
  SELECT sid, keys.join_key
  FROM (
    SELECT DISTINCT a.join_key
    FROM a_local a
  ) AS keys;

  RETURN QUERY
  SELECT b.id, b.join_key, b.payload, b.updated_at
  FROM b_remote_ft b
  JOIN semijoin_keys_stage_ft k
    ON k.join_key = b.join_key
   AND k.session_id = sid;

  DELETE FROM semijoin_keys_stage_ft
  WHERE session_id = sid;
EXCEPTION WHEN OTHERS THEN
  DELETE FROM semijoin_keys_stage_ft
  WHERE session_id = sid;
  RAISE;
END;
$$;

DROP FUNCTION IF EXISTS fetch_b_semijoin_auto(integer, integer, integer, text);
CREATE OR REPLACE FUNCTION fetch_b_semijoin_auto(
  key_threshold_batch integer DEFAULT 1500,
  key_threshold_staged integer DEFAULT 50000,
  chunk_size integer DEFAULT 500,
  mode text DEFAULT 'auto'
)
RETURNS TABLE (
  strategy text,
  id bigint,
  join_key int,
  payload text,
  updated_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
  distinct_keys integer;
  chosen text;
BEGIN
  SELECT count(*)
  INTO distinct_keys
  FROM (SELECT DISTINCT a.join_key FROM a_local a) q;

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
    SELECT chosen, t.id, t.join_key, t.payload, t.updated_at
    FROM fetch_b_semijoin(chunk_size) AS t;
  ELSIF chosen = 'staged_remote_join' THEN
    RETURN QUERY
    SELECT chosen, t.id, t.join_key, t.payload, t.updated_at
    FROM fetch_b_semijoin_staged() AS t;
  ELSIF chosen = 'baseline_remote_scan' THEN
    RETURN QUERY
    SELECT chosen, b.id, b.join_key, b.payload, b.updated_at
    FROM b_remote_ft b;
  ELSE
    RAISE EXCEPTION 'mode must be auto|batched_any|staged_remote_join|baseline_remote_scan';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS semijoin_run_metrics (
  run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_ts timestamptz NOT NULL DEFAULT now(),
  strategy text NOT NULL,
  distinct_keys integer NOT NULL,
  chunk_size integer,
  remote_rows bigint NOT NULL,
  join_rows bigint NOT NULL,
  elapsed_ms numeric(12,3) NOT NULL
);

DROP FUNCTION IF EXISTS benchmark_semijoin_strategies(integer, integer);
CREATE OR REPLACE FUNCTION benchmark_semijoin_strategies(
  chunk_size integer DEFAULT 500,
  key_threshold integer DEFAULT 1500
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
  SELECT count(*) INTO dk FROM (SELECT DISTINCT a.join_key FROM a_local a) q;

  t0 := clock_timestamp();
  WITH remote AS MATERIALIZED (
    SELECT * FROM b_remote_ft
  )
  SELECT (SELECT count(*) FROM remote),
         (SELECT count(*) FROM a_local a JOIN remote r ON r.join_key = a.join_key)
  INTO rr, jr;
  RETURN QUERY SELECT 'baseline_remote_scan', dk, rr, jr,
    EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0;

  t0 := clock_timestamp();
  WITH remote AS MATERIALIZED (
    SELECT * FROM fetch_b_semijoin(chunk_size)
  )
  SELECT (SELECT count(*) FROM remote),
         (SELECT count(*) FROM a_local a JOIN remote r ON r.join_key = a.join_key)
  INTO rr, jr;
  RETURN QUERY SELECT 'batched_any', dk, rr, jr,
    EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0;

  t0 := clock_timestamp();
  WITH remote AS MATERIALIZED (
    SELECT * FROM fetch_b_semijoin_staged()
  )
  SELECT (SELECT count(*) FROM remote),
         (SELECT count(*) FROM a_local a JOIN remote r ON r.join_key = a.join_key)
  INTO rr, jr;
  RETURN QUERY SELECT 'staged_remote_join', dk, rr, jr,
    EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0;
END;
$$;

DROP FUNCTION IF EXISTS run_and_log_benchmark(integer, integer);
CREATE OR REPLACE FUNCTION run_and_log_benchmark(
  chunk_size integer DEFAULT 500,
  key_threshold integer DEFAULT 1500
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
    FROM benchmark_semijoin_strategies(chunk_size, key_threshold)
  ), ins AS (
    INSERT INTO semijoin_run_metrics (strategy, distinct_keys, chunk_size, remote_rows, join_rows, elapsed_ms)
    SELECT r.strategy, r.distinct_keys, chunk_size, r.remote_rows, r.join_rows, r.elapsed_ms
    FROM results r
    RETURNING 1
  )
  SELECT r.strategy, r.distinct_keys, r.remote_rows, r.join_rows, r.elapsed_ms
  FROM results r;
END;
$$;
