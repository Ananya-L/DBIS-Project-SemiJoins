$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryJson = "reports/addons_summary_$timestamp.json"
$matrixCsv = "reports/strategy_matrix_$timestamp.csv"
$guardCsv = "reports/regression_guard_$timestamp.csv"
$anomalyCsv = "reports/anomalies_$timestamp.csv"

Write-Host '=== Addons Suite ==='
docker compose up -d | Out-Null

# Ensure advanced SQL objects exist.
Get-Content infra/site-a-init/03_advanced_tools.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-Null

Write-Host '1) Running strategy matrix'
Get-Content scripts/strategy_matrix.sql |
  docker exec -i dbis_site_a psql -U postgres -d site_a_db --csv -v ON_ERROR_STOP=1 -f - > $matrixCsv

Write-Host '2) Running anomaly detection'
Get-Content scripts/anomaly_detection.sql |
  docker exec -i dbis_site_a psql -U postgres -d site_a_db --csv -v ON_ERROR_STOP=1 -f - > $anomalyCsv

Write-Host '3) Running regression guard'
Get-Content scripts/regression_guard.sql |
  docker exec -i dbis_site_a psql -U postgres -d site_a_db --csv -v ON_ERROR_STOP=1 -v threshold_pct=20 -f - > $guardCsv

# Build simple JSON summary from CSV outputs.
$guardRows = (Import-Csv $guardCsv)
$regressed = @($guardRows | Where-Object { $_.guard_status -eq 'regressed' }).Count
$ok = @($guardRows | Where-Object { $_.guard_status -eq 'ok' }).Count
$insufficient = @($guardRows | Where-Object { $_.guard_status -eq 'insufficient-history' }).Count

$summary = [ordered]@{
  generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
  artifacts = [ordered]@{
    strategy_matrix_csv = $matrixCsv
    anomaly_csv = $anomalyCsv
    regression_guard_csv = $guardCsv
  }
  regression_guard = [ordered]@{
    ok = $ok
    regressed = $regressed
    insufficient_history = $insufficient
  }
}

$summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryJson -Encoding UTF8

Write-Host "Summary JSON: $summaryJson"
Write-Host '=== Addons Suite Complete ==='
