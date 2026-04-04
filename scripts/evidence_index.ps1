$ErrorActionPreference = 'Stop'

$reportDir = Join-Path $PWD 'reports'
$bundlePattern = 'submission_bundle_*.zip'
$files = @()

if (Test-Path $reportDir) {
  $files += Get-ChildItem $reportDir -File | Sort-Object LastWriteTime -Descending
}
$files += Get-ChildItem . -Filter $bundlePattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

$indexPath = Join-Path $reportDir ('evidence_index_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.md')

$rows = $files | ForEach-Object {
  [pscustomobject]@{
    Name = $_.Name
    SizeKB = [math]::Round($_.Length / 1KB, 2)
    Modified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    Path = $_.FullName
  }
}

$topReports = $rows | Select-Object -First 25

$md = @"
# Evidence Index

Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

## Latest Artifacts

| Name | Size (KB) | Modified | Path |
|---|---:|---|---|
$(($topReports | ForEach-Object { "| $($_.Name) | $($_.SizeKB) | $($_.Modified) | $($_.Path) |" }) -join "`n")

## Recommended Evidence Sequence

1. Run `scripts/environment_sanity.ps1`.
2. Run `scripts/run_full_demo.ps1`.
3. Run `scripts/judge_rehearsal.ps1`.
4. Run `scripts/run_fault_tests.ps1`.
5. Run `scripts/quality_gate.ps1`.
6. Open `docs/ELITE_PACK.md` and the latest `reports/showcase_*.html`.
"@

Set-Content -Path $indexPath -Value $md -Encoding UTF8
Write-Host "Evidence index written to $indexPath"
