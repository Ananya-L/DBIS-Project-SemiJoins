$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportPath = "reports/report_$timestamp.md"

Write-Host "Generating report: $reportPath"

docker compose up -d | Out-Null

$sectionCore = Get-Content scripts/benchmark.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String
$sectionBonus = Get-Content scripts/bonus_benchmark.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String
$sectionSelectivity = Get-Content scripts/selectivity_profile.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String
$sectionStats = Get-Content scripts/statistical_benchmark.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String

$md = @"
# DBIS Semijoin Auto Report

Generated at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")

## Environment

- Docker services: `dbis_site_a`, `dbis_site_b`
- Database: `site_a_db` (coordinator), `site_b_db` (remote)

## Core Benchmark Output

~~~text
$sectionCore
~~~

## Bonus Benchmark Output

~~~text
$sectionBonus
~~~

## Selectivity Profile Output

~~~text
$sectionSelectivity
~~~

## Statistical Benchmark Output

~~~text
$sectionStats
~~~

## Quick Conclusions Template

1. Correctness: verify `rowcount_equal = t` in core and auto checks.
2. Best average strategy: see `run_statistical_benchmark` top row by `avg_ms`.
3. Selectivity behavior: see `winner` column in selectivity profile output.
4. Reproducibility: rerun this script to produce a new timestamped report.
"@

Set-Content -Path $reportPath -Value $md -Encoding UTF8
Write-Host "Report created at $reportPath"
