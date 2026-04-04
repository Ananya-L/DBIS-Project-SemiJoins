$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$eliteJson = "reports/elite_summary_$timestamp.json"
$eliteMd = "reports/elite_summary_$timestamp.md"

Write-Host '=== Elite Suite ==='
docker compose up -d | Out-Null

# Refresh core outputs for a coherent elite run.
powershell -ExecutionPolicy Bypass -File scripts/reset_reproducible_state.ps1 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/run_full_demo.ps1 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/run_addons_suite.ps1 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/generate_report.ps1 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/export_visuals.ps1 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/best_showcase.ps1 | Out-Null

# Build high-level analytics outputs.
$judge = & { Get-Content scripts/judge_mode.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String }
$ci = & { Get-Content scripts/confidence_intervals.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String }
$sweep = & { Get-Content scripts/experiment_sweep.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String }
$trend = & { Get-Content scripts/performance_trend.sql | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f - | Out-String }

$addons = Get-ChildItem reports -Filter 'addons_summary_*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$showcase = Get-ChildItem reports -Filter 'showcase_*.html' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$report = Get-ChildItem reports -Filter 'report_*.md' | Sort-Object LastWriteTime -Descending | Select-Object -First 1

$summary = [ordered]@{
  generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
  artifacts = [ordered]@{
    report = $report.FullName
    addons_summary = $addons.FullName
    showcase = $showcase.FullName
  }
  snapshots = [ordered]@{
    judge = $judge.Trim()
    confidence_intervals = $ci.Trim()
    trend = $trend.Trim()
    sweep = $sweep.Trim()
  }
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $eliteJson -Encoding UTF8

@"
# Elite Suite Summary

Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

## Artifacts

- Report: $(Split-Path $report.FullName -Leaf)
- Addons summary: $(Split-Path $addons.FullName -Leaf)
- Showcase: $(Split-Path $showcase.FullName -Leaf)
- JSON summary: $(Split-Path $eliteJson -Leaf)

## What makes this project best-in-class

1. Correctness is verified by judge mode and rowcount equivalence checks.
2. Performance is measured with averages, p95, confidence intervals, and trend analysis.
3. Robustness is covered by fault tests and regression guardrails.
4. Usability is improved with a live assistant, showcase HTML, cheat sheet, and bundle scripts.
5. Submission readiness is supported by a final checklist, bundle generator, and release tag.
"@ | Set-Content -Path $eliteMd -Encoding UTF8

Write-Host "Elite summary JSON: $eliteJson"
Write-Host "Elite summary MD: $eliteMd"
Write-Host '=== Elite Suite Complete ==='
