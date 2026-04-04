$ErrorActionPreference = 'Stop'

Write-Host '=== DBIS Semijoin Full Demo ==='
Write-Host '1) Starting containers'
docker compose up -d | Out-Null

docker compose ps

Write-Host '2) Applying latest schema/functions'
Get-Content infra/site-b-init/02_semijoin_stage.sql | docker exec -i dbis_site_b psql -U postgres -d site_b_db -v ON_ERROR_STOP=1 -f - | Out-Null
Get-Content infra/site-a-init/02_fdw_semijoin.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-Null

Write-Host '3) Running core benchmark'
Get-Content scripts/benchmark.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -

Write-Host '4) Running bonus benchmark'
Get-Content scripts/bonus_benchmark.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -

Write-Host '5) Running selectivity profile (low/medium/high tiers)'
Get-Content scripts/selectivity_profile.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -

Write-Host '6) Final compact summary'
@'
WITH latest AS (
  SELECT m.*
  FROM semijoin_run_metrics m
  WHERE m.run_id IN (
    SELECT run_id
    FROM semijoin_run_metrics
    ORDER BY run_id DESC
    LIMIT 3
  )
)
SELECT strategy,
       distinct_keys,
       chunk_size,
       remote_rows,
       join_rows,
       elapsed_ms
FROM latest
ORDER BY elapsed_ms ASC;
'@ | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -

Write-Host '=== Demo completed ==='
