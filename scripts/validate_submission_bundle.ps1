param(
  [string]$BundlePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($BundlePath)) {
  $bundle = Get-ChildItem -Path . -Filter 'submission_bundle_*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $bundle) {
    throw 'No submission bundle zip found. Run scripts/create_submission_bundle.ps1 first.'
  }
  $BundlePath = $bundle.FullName
}

$requiredPatterns = @(
  'README.md',
  'docker-compose.yml',
  'docs/',
  'infra/',
  'scripts/'
)

$tmp = Join-Path $env:TEMP ('bundle_validate_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Expand-Archive -Path $BundlePath -DestinationPath $tmp -Force

$missing = @()
foreach ($pattern in $requiredPatterns) {
  if (-not (Get-ChildItem -Path $tmp -Recurse -Filter (Split-Path $pattern -Leaf) -ErrorAction SilentlyContinue)) {
    $missing += $pattern
  }
}

$result = [ordered]@{
  bundle = (Resolve-Path $BundlePath).Path
  validated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
  missing = $missing
  status = if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }
}

$result | ConvertTo-Json -Depth 4

if ($missing.Count -gt 0) {
  Write-Host 'Missing required bundle contents:'
  $missing | ForEach-Object { Write-Host "- $_" }
  exit 1
}

Write-Host 'Submission bundle validation passed.'
