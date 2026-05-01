param(
    [string]$Psql = "$HOME/pg_custom/bin/psql",
    [string]$LocalPort = "5432",
    [string]$RemotePort = "5433",
    [string]$Database = "postgres"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "== Setting up remote staging table =="
& $Psql -h localhost -p $RemotePort -d $Database -f "$Root/BONUS_SITE_B_STAGE.sql"

Write-Host "== Installing local bonus functions =="
& $Psql -h localhost -p $LocalPort -d $Database -f "$Root/BONUS_SEMIJOIN_STRATEGIES.sql"

Write-Host "== Running strategy benchmark demo =="
& $Psql -h localhost -p $LocalPort -d $Database -f "$Root/BONUS_BENCHMARK_DEMO.sql"

Write-Host "== Running selectivity profile =="
& $Psql -h localhost -p $LocalPort -d $Database -f "$Root/BONUS_SELECTIVITY_PROFILE.sql"

Write-Host "== Bonus demo complete =="

