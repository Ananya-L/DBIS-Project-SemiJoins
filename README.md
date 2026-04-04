# DBIS Project: FDW Semijoin Prototype

This repository contains a complete, runnable two-site PostgreSQL prototype that demonstrates semijoin optimization using `postgres_fdw`.

## What is implemented

1. Site A local table: `a_local`.
2. Site B remote table: `b_remote`.
3. FDW foreign table on Site A: `b_remote_ft`.
4. Semijoin function on Site A: `fetch_b_semijoin(chunk_size)`.
5. Benchmark script comparing baseline join vs semijoin-based join.

## Why this is semijoin optimization

The optimization follows distributed semijoin flow:

1. Extract distinct local join keys from Site A.
2. Push those keys to Site B as batched filters (`= ANY(array)` on foreign relation).
3. Fetch only matching remote tuples.
4. Complete final join locally.

This avoids transferring unrelated tuples from Site B.

## Run instructions

Requirements:

1. Docker Desktop (or Docker Engine with Compose).

Start environment and run benchmark:

```powershell
docker compose up -d
powershell -ExecutionPolicy Bypass -File scripts/run_benchmark.ps1
```

Manual benchmark run:

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/benchmark.sql
```

Stop environment:

```powershell
docker compose down
```

## Important files

1. `docker-compose.yml`: Two PostgreSQL nodes.
2. `infra/site-b-init/01_schema.sql`: Remote table and data.
3. `infra/site-a-init/01_schema.sql`: Local table and data.
4. `infra/site-a-init/02_fdw_semijoin.sql`: FDW setup and semijoin function.
5. `scripts/benchmark.sql`: `EXPLAIN ANALYZE` and correctness check.

## Notes

1. This prototype is implementation-complete at SQL/FDW usage level.
2. It does not patch PostgreSQL C internals in `postgres_fdw.c` or `deparse.c`.
3. Use this for checkpoint demo and measurable validation of semijoin data-transfer reduction.
