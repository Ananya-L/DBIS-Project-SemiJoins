$ErrorActionPreference = 'Stop'

Write-Host '=== 3-Minute Judge Rehearsal ==='

docker compose up -d | Out-Null

Write-Host 'Step 1: Running compact judge mode output'
Get-Content scripts/judge_mode.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -

Write-Host 'Step 2: Locating latest chart artifact'
$latestChart = Get-ChildItem reports -Filter 'charts_*.html' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if ($null -ne $latestChart) {
  Write-Host "Latest chart: $($latestChart.FullName)"
} else {
  Write-Host 'No chart found. Run scripts/export_visuals.ps1 before demo.'
}

Write-Host 'Step 3: Core correctness proof query'
@'
WITH baseline AS (
  SELECT a.id AS a_id, b.id AS b_id
  FROM a_local a
  JOIN b_remote_ft b ON b.join_key = a.join_key
), auto_join AS (
  WITH r AS MATERIALIZED (
    SELECT id, join_key
    FROM fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
  )
  SELECT a.id AS a_id, r.id AS b_id
  FROM a_local a
  JOIN r ON r.join_key = a.join_key
)
SELECT
  (SELECT count(*) FROM baseline) AS baseline_rows,
  (SELECT count(*) FROM auto_join) AS auto_rows,
  ((SELECT count(*) FROM baseline) = (SELECT count(*) FROM auto_join)) AS rowcount_equal;
'@ | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -

Write-Host '=== Rehearsal complete ==='
