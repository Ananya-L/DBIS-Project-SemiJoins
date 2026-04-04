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
    SELECT b.id, b.join_key, b.payload, b.updated_at
    FROM b_remote_ft b
    WHERE b.join_key = ANY(key_batch);
  END LOOP;
END;
$$;
