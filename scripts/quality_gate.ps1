$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryPath = "reports/quality_gate_$timestamp.json"

Write-Host '=== Quality Gate ==='

$steps = [ordered]@{}

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  try {
    & $Action
    $steps[$Name] = 'PASS'
  } catch {
    $steps[$Name] = 'FAIL'
    $steps["${Name}_error"] = $_.Exception.Message
  }
}

Invoke-Step 'environment_sanity' { powershell -ExecutionPolicy Bypass -File scripts/environment_sanity.ps1 | Out-Null }
Invoke-Step 'bundle_validation' { powershell -ExecutionPolicy Bypass -File scripts/validate_submission_bundle.ps1 | Out-Null }
Invoke-Step 'regression_guard' { Get-Content scripts/regression_guard.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-Null }
Invoke-Step 'judge_mode' { Get-Content scripts/judge_mode.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-Null }

$allPass = ($steps.Values -notcontains 'FAIL')

$summary = [ordered]@{
  generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
  status = if ($allPass) { 'PASS' } else { 'FAIL' }
  steps = $steps
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host "Quality gate summary: $summaryPath"
if (-not $allPass) { exit 1 }
Write-Host '=== Quality Gate Complete ==='
