\timing on

-- Sweep selectivity bands and chunk sizes to produce a publication-style matrix.

WITH chunk_cfg AS (
  SELECT unnest(ARRAY[100, 250, 500, 1000, 2000]) AS chunk_size
), keybands AS (
  SELECT 'low'::text AS band, ARRAY[20010,20020,20030,20040,20050,20060,20070,20080,20090,20100]::int[] AS keys
  UNION ALL
  SELECT 'medium'::text AS band, ARRAY[2,3,4,5,6,7,8,9,10,12]::int[]
  UNION ALL
  SELECT 'high'::text AS band, ARRAY[4817,4818,4819,4820,4822,4823,4824,4825,4826,4827]::int[]
), sweeps AS (
  SELECT kb.band,
         cc.chunk_size,
         m.strategy,
         m.elapsed_ms,
         m.remote_rows,
         m.join_rows
  FROM keybands kb
  CROSS JOIN chunk_cfg cc
  CROSS JOIN LATERAL measure_workload_band(kb.keys, cc.chunk_size) AS m
)
SELECT *
FROM sweeps
ORDER BY band, chunk_size, strategy;
