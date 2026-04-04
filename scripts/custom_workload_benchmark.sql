\timing on

-- Usage example:
-- docker exec -i dbis_site_a psql -U postgres -d site_a_db \
--   -v min_key=1 -v max_key=500 -v chunk_size=500 -f /dev/stdin < scripts/custom_workload_benchmark.sql

\if :{?min_key}
\else
\set min_key 1
\endif

\if :{?max_key}
\else
\set max_key 500
\endif

\if :{?chunk_size}
\else
\set chunk_size 500
\endif

WITH cfg AS (
  SELECT :min_key::int AS min_key,
         :max_key::int AS max_key,
         :chunk_size::int AS chunk_size
), keyset AS (
  SELECT ARRAY(
    SELECT DISTINCT a.join_key
    FROM a_local a, cfg c
    WHERE a.join_key BETWEEN c.min_key AND c.max_key
    ORDER BY a.join_key
  ) AS keys,
  (SELECT chunk_size FROM cfg) AS chunk_size
), local_filtered AS (
  SELECT a.id, a.join_key
  FROM a_local a, keyset k
  WHERE a.join_key = ANY(k.keys)
), baseline AS (
  SELECT clock_timestamp() AS t0,
         (SELECT count(*)
          FROM local_filtered a
          JOIN b_remote_ft b
            ON b.join_key = a.join_key) AS join_rows,
         clock_timestamp() AS t1
), pushed AS (
  SELECT clock_timestamp() AS t0,
         (SELECT count(*)
          FROM local_filtered a
          JOIN b_remote_ft b
            ON b.join_key = a.join_key
          CROSS JOIN keyset k
          WHERE b.join_key = ANY(k.keys)) AS join_rows,
         (SELECT count(*)
          FROM b_remote_ft b, keyset k
          WHERE b.join_key = ANY(k.keys)) AS remote_rows,
         clock_timestamp() AS t1
), batched AS (
  SELECT clock_timestamp() AS t0,
         (SELECT count(*)
          FROM a_local a
          JOIN fetch_b_semijoin((SELECT chunk_size FROM keyset)) b
            ON b.join_key = a.join_key
          WHERE a.join_key BETWEEN :min_key::int AND :max_key::int) AS join_rows,
         clock_timestamp() AS t1
)
SELECT 'config' AS section,
       format('min_key=%s max_key=%s chunk_size=%s', c.min_key, c.max_key, c.chunk_size) AS detail,
       NULL::numeric AS elapsed_ms,
       NULL::bigint AS rows
FROM cfg c
UNION ALL
SELECT 'baseline_local_foreign',
       'join_rows',
       EXTRACT(EPOCH FROM (b.t1 - b.t0)) * 1000.0,
       b.join_rows
FROM baseline b
UNION ALL
SELECT 'pushed_direct_filter',
       'remote_rows',
       EXTRACT(EPOCH FROM (p.t1 - p.t0)) * 1000.0,
       p.remote_rows
FROM pushed p
UNION ALL
SELECT 'batched_semijoin_function',
       'join_rows',
       EXTRACT(EPOCH FROM (bt.t1 - bt.t0)) * 1000.0,
       bt.join_rows
FROM batched bt;
