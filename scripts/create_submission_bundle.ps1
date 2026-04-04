$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$bundleDir = "submission_bundle_$timestamp"
$bundleZip = "submission_bundle_$timestamp.zip"

Write-Host "Preparing bundle folder: $bundleDir"
if (Test-Path $bundleDir) {
  Remove-Item -Recurse -Force $bundleDir
}
New-Item -ItemType Directory -Path $bundleDir | Out-Null

$pathsToCopy = @(
  'README.md',
  'docker-compose.yml',
  'fdw_semijoin_demo.sql',
  'BONUS_FEATURES_REPORT.md',
  'infra',
  'scripts',
  'docs'
)

foreach ($p in $pathsToCopy) {
  if (Test-Path $p) {
    Copy-Item -Recurse -Force $p (Join-Path $bundleDir $p)
  }
}

# Include reports and charts if they exist.
if (Test-Path 'reports') {
  Copy-Item -Recurse -Force 'reports' (Join-Path $bundleDir 'reports')
}

# Exclude large/unnecessary local development artifacts from bundle.
$exclude = @(
  (Join-Path $bundleDir 'postgres-src'),
  (Join-Path $bundleDir '.git')
)
foreach ($e in $exclude) {
  if (Test-Path $e) {
    Remove-Item -Recurse -Force $e
  }
}

if (Test-Path $bundleZip) {
  Remove-Item -Force $bundleZip
}
Compress-Archive -Path "$bundleDir\*" -DestinationPath $bundleZip -CompressionLevel Optimal

Write-Host "Bundle created: $bundleZip"
Write-Host "Bundle folder kept at: $bundleDir"
