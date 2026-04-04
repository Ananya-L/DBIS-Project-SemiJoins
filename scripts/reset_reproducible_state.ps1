$ErrorActionPreference = 'Stop'

Write-Host 'Resetting to reproducible deterministic state...'
docker compose down -v | Out-Null
docker compose up -d | Out-Null

Write-Host 'Waiting for containers...'
Start-Sleep -Seconds 6

# Fresh volumes trigger docker-entrypoint SQL init scripts exactly once,
# yielding deterministic seeded state without duplicate inserts.

Write-Host 'Deterministic reset complete.'
"SELECT (SELECT count(*) FROM a_local) AS a_rows, (SELECT count(*) FROM b_remote_ft) AS b_rows;" | docker exec -i dbis_site_a psql -U postgres -d site_a_db -v ON_ERROR_STOP=1 -f -
