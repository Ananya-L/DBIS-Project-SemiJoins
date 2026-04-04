$ErrorActionPreference = 'Stop'

Write-Host '=== Environment Sanity Check ==='

$results = [ordered]@{}

$results.docker = [bool](Get-Command docker -ErrorAction SilentlyContinue)
$results.psql = [bool](Get-Command psql -ErrorAction SilentlyContinue)

docker compose version | Out-Null
$results.compose = ($LASTEXITCODE -eq 0)

$composePs = docker compose ps
$results.site_a = [bool]($composePs | Select-String 'dbis_site_a' | Select-String 'Up')
$results.site_b = [bool]($composePs | Select-String 'dbis_site_b' | Select-String 'Up')

try {
  $tag = git tag -l 'v1.0-submission'
  $results.release_tag = [bool]$tag
} catch {
  $results.release_tag = $false
}

$summary = [ordered]@{
  timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
  checks = $results
  status = if ($results.Values -notcontains $false) { 'PASS' } else { 'WARN' }
}

$summary | ConvertTo-Json -Depth 4

if ($results.Values -contains $false) {
  Write-Host 'One or more checks returned false.'
}
Write-Host '=== Environment Sanity Complete ==='
