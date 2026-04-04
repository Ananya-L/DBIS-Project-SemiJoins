$ErrorActionPreference = 'Stop'

function Invoke-Strict {
  param([scriptblock]$Cmd)
  & $Cmd
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE"
  }
}

Write-Host '=== Live Demo Assistant ==='
Write-Host 'Step 1: Ensure containers are running'
Invoke-Strict { docker compose up -d | Out-Null }
Invoke-Strict { docker compose ps }

Write-Host 'Step 2: Compact judge verdict'
Invoke-Strict { Get-Content scripts/judge_mode.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - }

Write-Host 'Step 3: Auto-tuner recommendation'
Invoke-Strict { Get-Content scripts/auto_tune.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - }

Write-Host 'Step 4: Performance trend snapshot'
Invoke-Strict { Get-Content scripts/performance_trend.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - }

Write-Host 'Step 5: Fast custom workload (1..500 keys)'
Invoke-Strict {
  Get-Content scripts/custom_workload_benchmark.sql |
    docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -v min_key=1 -v max_key=500 -v chunk_size=500 -f -
}

Write-Host '=== Live Demo Assistant Complete ==='
