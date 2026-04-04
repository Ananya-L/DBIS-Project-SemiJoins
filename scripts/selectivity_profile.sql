\timing on

-- Profiles three selectivity tiers by key frequency and compares
-- baseline remote scan versus pushed remote filtering.

DROP FUNCTION IF EXISTS profile_selectivity_once(integer[]);
CREATE OR REPLACE FUNCTION profile_selectivity_once(keys integer[])
RETURNS TABLE (
  num_keys integer,
  local_rows bigint,
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
  lr bigint;
  bjr bigint;
  prr bigint;
  pjr bigint;
BEGIN
  SELECT count(*)
  INTO lr
  FROM a_local a
  WHERE a.join_key = ANY(keys);

  t0 := clock_timestamp();
  WITH a_filtered AS MATERIALIZED (
    SELECT a.id, a.join_key
    FROM a_local a
    WHERE a.join_key = ANY(keys)
  )
  SELECT count(*)
  INTO bjr
  FROM a_filtered a
  JOIN b_remote_ft b
    ON b.join_key = a.join_key;

  baseline_ms := EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0;

  t0 := clock_timestamp();
  WITH b_filtered AS MATERIALIZED (
    SELECT b.id, b.join_key
    FROM b_remote_ft b
    WHERE b.join_key = ANY(keys)
  )
  SELECT (SELECT count(*) FROM b_filtered),
         (SELECT count(*) FROM a_local a JOIN b_filtered b ON b.join_key = a.join_key)
  INTO prr, pjr;

  pushed_ms := EXTRACT(EPOCH FROM clock_timestamp() - t0) * 1000.0;

  RETURN QUERY
  SELECT cardinality(keys), lr, bjr, prr, pjr, baseline_ms, pushed_ms;
END;
$$;

WITH key_freq AS (
  SELECT a.join_key,
         count(*) AS freq
  FROM a_local a
  GROUP BY a.join_key
), ranked AS (
  SELECT k.join_key,
         k.freq,
         ntile(3) OVER (ORDER BY k.freq ASC, k.join_key ASC) AS tier_idx
  FROM key_freq k
), picks AS (
  SELECT 'low'::text AS tier,
         ARRAY(
           SELECT r.join_key
           FROM ranked r
           WHERE r.tier_idx = 1
           ORDER BY r.freq ASC, r.join_key ASC
           LIMIT 10
         ) AS keys
  UNION ALL
  SELECT 'medium'::text AS tier,
         ARRAY(
           SELECT r.join_key
           FROM ranked r
           WHERE r.tier_idx = 2
           ORDER BY abs(r.freq - (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY freq) FROM key_freq)), r.join_key ASC
           LIMIT 10
         ) AS keys
  UNION ALL
  SELECT 'high'::text AS tier,
         ARRAY(
           SELECT r.join_key
           FROM ranked r
           WHERE r.tier_idx = 3
           ORDER BY r.freq DESC, r.join_key ASC
           LIMIT 10
         ) AS keys
)
SELECT p.tier,
       m.num_keys,
       m.local_rows,
       m.baseline_join_rows,
       m.pushed_remote_rows,
       m.pushed_join_rows,
       m.baseline_ms,
       m.pushed_ms,
       round((m.baseline_ms - m.pushed_ms)::numeric, 3) AS delta_ms,
       CASE
         WHEN m.pushed_ms < m.baseline_ms THEN 'pushed_filter_win'
         ELSE 'baseline_scan_win'
       END AS winner,
       p.keys
FROM picks p
CROSS JOIN LATERAL profile_selectivity_once(p.keys) AS m
ORDER BY CASE p.tier WHEN 'low' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END;
