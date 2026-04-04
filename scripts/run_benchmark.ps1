$ErrorActionPreference = 'Stop'

Write-Host 'Starting Site A and Site B...'
docker compose up -d

Write-Host 'Waiting for PostgreSQL containers to become healthy...'
Start-Sleep -Seconds 8

Write-Host 'Running benchmark on Site A...'
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/benchmark.sql
