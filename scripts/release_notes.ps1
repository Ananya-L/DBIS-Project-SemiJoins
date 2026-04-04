$ErrorActionPreference = 'Stop'

$latestReport = Get-ChildItem reports -Filter 'elite_summary_*.md' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestShowcase = Get-ChildItem reports -Filter 'showcase_*.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestBundle = Get-ChildItem -Path . -Filter 'submission_bundle_*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

$notes = @"
# Release Notes

Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

## What is included

- Two-site PostgreSQL FDW semijoin prototype
- Core, bonus, addon, and elite analytics pipelines
- Rehearsal, judge mode, fault tests, regression guard, and tuning utilities
- Visual dashboard, showcase page, and submission bundle tooling

## Current best artifacts

- Elite summary: $(if ($latestReport) { $latestReport.FullName } else { 'not found' })
- Showcase: $(if ($latestShowcase) { $latestShowcase.FullName } else { 'not found' })
- Submission bundle: $(if ($latestBundle) { $latestBundle.FullName } else { 'not found' })

## Recommended submission stance

1. Use the judge rehearsal to demonstrate compact PASS output.
2. Use the elite summary and showcase for the strongest story.
3. Use the submission-ready commands file for exact run order.
4. Keep the release tag `v1.0-submission` fixed for viva reference.
"@

$releasePath = 'docs/RELEASE_NOTES.md'
Set-Content -Path $releasePath -Value $notes -Encoding UTF8
Write-Host "Release notes written to $releasePath"
