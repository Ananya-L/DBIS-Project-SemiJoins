$ErrorActionPreference = 'Stop'

function Invoke-SqlA {
  param([string]$Sql)
  $Sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -
  if ($LASTEXITCODE -ne 0) {
    throw "psql command failed with exit code $LASTEXITCODE"
  }
}

Write-Host '=== Fault Injection Tests ==='
docker compose up -d | Out-Null

$passCount = 0
$failCount = 0

# Test 1: Baseline connectivity
try {
  Invoke-SqlA "SELECT count(*) FROM b_remote_ft;" | Out-Null
  Write-Host '[PASS] Baseline FDW connectivity'
  $passCount++
} catch {
  Write-Host '[FAIL] Baseline FDW connectivity'
  $failCount++
}

# Test 2: Remote restart recovery
try {
  docker restart dbis_site_b | Out-Null
  Start-Sleep -Seconds 3
  Invoke-SqlA "SELECT count(*) FROM b_remote_ft;" | Out-Null
  Write-Host '[PASS] Recovery after Site B restart'
  $passCount++
} catch {
  Write-Host '[FAIL] Recovery after Site B restart'
  $failCount++
}

# Test 3: Wrong credentials should fail, then restore
try {
  Invoke-SqlA "ALTER USER MAPPING FOR CURRENT_USER SERVER site_b OPTIONS (SET password 'wrong_password');" | Out-Null
  $failedAsExpected = $false
  "SET statement_timeout='5s'; SELECT count(*) FROM b_remote_ft;" | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-Null
  if ($LASTEXITCODE -ne 0) {
    $failedAsExpected = $true
  }

  Invoke-SqlA "ALTER USER MAPPING FOR CURRENT_USER SERVER site_b OPTIONS (SET password 'postgres');" | Out-Null
  Invoke-SqlA "SELECT count(*) FROM b_remote_ft;" | Out-Null

  if ($failedAsExpected) {
    Write-Host '[PASS] Credential failure detected and restored'
    $passCount++
  } else {
    Write-Host '[FAIL] Credential failure test did not fail as expected'
    $failCount++
  }
} catch {
  Write-Host '[FAIL] Credential failure/recovery block'
  $failCount++
}

Write-Host "Summary: PASS=$passCount FAIL=$failCount"
if ($failCount -gt 0) {
  exit 1
}
Write-Host '=== Fault tests completed successfully ==='
