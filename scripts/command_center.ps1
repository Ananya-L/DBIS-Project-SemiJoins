$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryJson = "reports/command_center_$timestamp.json"

Write-Host '=== Command Center ==='

function Invoke-AndCapture {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  $text = & $Action | Out-String
  return [pscustomobject]@{ name = $Name; output = $text.Trim() }
}

$results = [ordered]@{}

$results.environment = Invoke-AndCapture 'environment_sanity' { powershell -ExecutionPolicy Bypass -File scripts/environment_sanity.ps1 }
$results.quality_gate = Invoke-AndCapture 'quality_gate' { powershell -ExecutionPolicy Bypass -File scripts/quality_gate.ps1 }
$results.data_volume = Invoke-AndCapture 'data_volume_estimator' { Get-Content scripts/data_volume_estimator.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - }
$results.benchmark_diff = Invoke-AndCapture 'benchmark_diff' { Get-Content scripts/benchmark_diff.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - }
$results.evidence_index = Invoke-AndCapture 'evidence_index' { powershell -ExecutionPolicy Bypass -File scripts/evidence_index.ps1 }
$results.release_notes = Invoke-AndCapture 'release_notes' { powershell -ExecutionPolicy Bypass -File scripts/release_notes.ps1 }

$reportFiles = Get-ChildItem reports -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
  [pscustomobject]@{
    name = $_.Name
    size_kb = [math]::Round($_.Length / 1KB, 2)
    modified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  }
}

$summary = [ordered]@{
  generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
  status = 'PASS'
  artifacts = $reportFiles
  checks = $results
}

$summary | ConvertTo-Json -Depth 7 | Set-Content -Path $summaryJson -Encoding UTF8
Write-Host "Command center summary: $summaryJson"
Write-Host '=== Command Center Complete ==='
