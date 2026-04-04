-- FDW Semijoin Demo (Site A local, Site B remote)
-- Goal: fetch only tuples from B whose join keys appear in local A.

-- 1) FDW setup on Site A
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

DROP SERVER IF EXISTS site_b CASCADE;
CREATE SERVER site_b
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host '127.0.0.1', dbname 'site_b_db', port '5432');

-- Update with real credentials for Site B.
CREATE USER MAPPING FOR CURRENT_USER
  SERVER site_b
  OPTIONS (user 'site_b_user', password 'site_b_password');

-- 2) Local relation on Site A
DROP TABLE IF EXISTS a_local;
CREATE TABLE a_local (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  join_key int NOT NULL,
  payload text
);

-- 3) Foreign relation definition for relation physically stored on Site B
DROP FOREIGN TABLE IF EXISTS b_remote_ft;
CREATE FOREIGN TABLE b_remote_ft (
  join_key int,
  payload text,
  updated_at timestamptz
)
SERVER site_b
OPTIONS (schema_name 'public', table_name 'b_remote');

-- 4) Seed sample local data (optional)
INSERT INTO a_local (join_key, payload)
VALUES (1, 'a1'), (1, 'a1-dup'), (2, 'a2'), (4, 'a4'), (9, 'a9');

-- 5) Semijoin implementation
-- Strategy:
--   a) Collect DISTINCT local keys.
--   b) Send keys to Site B in chunks using "= ANY($1)" filter.
--   c) Union all remote results.
-- This uses existing FDW pushdown of simple predicates.

DROP FUNCTION IF EXISTS fetch_b_semijoin(integer);
CREATE OR REPLACE FUNCTION fetch_b_semijoin(chunk_size integer DEFAULT 1000)
RETURNS TABLE (
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
      SELECT DISTINCT join_key,
             ((row_number() OVER (ORDER BY join_key) - 1) / chunk_size) AS grp
      FROM a_local
    )
    SELECT array_agg(join_key ORDER BY join_key)
    FROM keys
    GROUP BY grp
    ORDER BY grp
  LOOP
    RETURN QUERY
    SELECT b.join_key, b.payload, b.updated_at
    FROM b_remote_ft b
    WHERE b.join_key = ANY(key_batch);
  END LOOP;
END;
$$;

-- 6) Use fetched subset in local final join
-- MATERIALIZED ensures one-time remote retrieval for stable plans.
WITH b_needed AS MATERIALIZED (
  SELECT *
  FROM fetch_b_semijoin(500)
)
SELECT a.id, a.join_key, a.payload AS a_payload, b.payload AS b_payload, b.updated_at
FROM a_local a
JOIN b_needed b
  ON b.join_key = a.join_key
ORDER BY a.id;

-- 7) Verification: inspect remote SQL and row reduction
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
WITH b_needed AS MATERIALIZED (
  SELECT *
  FROM fetch_b_semijoin(500)
)
SELECT a.id, a.join_key, b.payload
FROM a_local a
JOIN b_needed b
  ON b.join_key = a.join_key;

-- Notes:
-- - For large key sets, tune chunk_size to avoid huge arrays and long SQL packets.
-- - Add index on Site B: CREATE INDEX ON b_remote(join_key);
-- - This avoids shipping all B rows to A and emulates distributed semijoin behavior.
