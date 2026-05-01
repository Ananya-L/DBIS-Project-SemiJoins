# DBIS Project: FDW Semijoin Prototype

This repository contains a complete, runnable two-site PostgreSQL prototype that demonstrates semijoin optimization using `postgres_fdw`.

## What is implemented

1. Site A local table: `a_local`.
2. Site B remote table: `b_remote`.
3. FDW foreign table on Site A: `b_remote_ft`.
4. Semijoin function on Site A: `fetch_b_semijoin(chunk_size)`.
5. Bonus staged semijoin strategy via remote key staging table.
6. Auto strategy chooser: batched, staged, or baseline fallback.
7. Benchmark scripts comparing strategies and logging metrics.

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

Run full end-to-end demo (core + bonus + selectivity profiler + summary):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_full_demo.ps1
```

Run reproducible reset (fresh deterministic state):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/reset_reproducible_state.ps1
```

Run fault-injection tests:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_fault_tests.ps1
```

Run compact judge mode:

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/judge_mode.sql
```

Run threshold auto-tuner:

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/auto_tune.sql
```

Export CSV and chart visuals:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/export_visuals.ps1
```

Run 3-minute judge rehearsal:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/judge_rehearsal.ps1
```

Create final submission bundle:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/create_submission_bundle.ps1
```

Run statistical benchmark (avg/p95/stddev across multiple rounds):

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/statistical_benchmark.sql
```

Generate timestamped auto report (markdown):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_report.ps1
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
3. `infra/site-b-init/02_semijoin_stage.sql`: Remote staging table for bonus strategy.
4. `infra/site-a-init/01_schema.sql`: Local table and data.
5. `infra/site-a-init/02_fdw_semijoin.sql`: FDW setup and all semijoin strategies.
6. `scripts/benchmark.sql`: Core `EXPLAIN ANALYZE` and correctness check.
7. `scripts/bonus_benchmark.sql`: Auto strategy, staged strategy, and metric logging.
8. `scripts/selectivity_profile.sql`: Low/medium/high selectivity profiling with winner label.
9. `scripts/run_full_demo.ps1`: One-command, submission-ready demo runner.
10. `scripts/statistical_benchmark.sql`: Multi-run statistical benchmark (avg/p95/stddev).
11. `scripts/generate_report.ps1`: Auto-generates a timestamped markdown report in `reports/`.
12. `docs/VIVA_PACK.md`: Slide outline and speaking scripts for viva.
13. `infra/site-a-init/03_advanced_tools.sql`: auto-tuner and tuning-history objects.
14. `scripts/judge_mode.sql`: compact PASS/FAIL plus strategy ranking output.
15. `scripts/auto_tune.sql`: executes threshold auto-tuner and history view.
16. `scripts/run_fault_tests.ps1`: restart and credential fault injection with recovery checks.
17. `scripts/reset_reproducible_state.ps1`: deterministic reset flow.
18. `scripts/export_visuals.ps1`: CSV exports and chart HTML generation.
19. `docs/ARCHITECTURE.md`: architecture diagram.
20. `docs/SUBMISSION_CHECKLIST.md`: final validation checklist.
21. `docs/RISK_REGISTER.md`: final risk and mitigation table.
22. `docs/DEMO_CHEATSHEET.md`: quick command runbook for live demo.
23. `dashboard/index.html`: lightweight local chart dashboard for CSV outputs.
24. `scripts/judge_rehearsal.ps1`: compact 3-minute rehearsal script.
25. `scripts/create_submission_bundle.ps1`: packages submission artifacts into zip.

## Bonus implementations

1. Staged key semijoin (`fetch_b_semijoin_staged`):
   - Writes distinct local keys to a remote staging table.
   - Performs remote-side join between staged keys and remote relation.
2. Adaptive strategy (`fetch_b_semijoin_auto`):
   - Chooses `batched_any`, `staged_remote_join`, or `baseline_remote_scan` by key cardinality thresholds.
3. Benchmark framework:
   - `benchmark_semijoin_strategies` compares three strategies in one call.
   - `run_and_log_benchmark` stores experiment results in `semijoin_run_metrics`.

Run bonus benchmark:

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/bonus_benchmark.sql
```

Run selectivity profile:

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/selectivity_profile.sql
```

Run statistical benchmark:

```powershell
docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/statistical_benchmark.sql
```

Generate report:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_report.ps1
```

## Troubleshooting Checklist

1. Containers not running:

- Run `docker compose up -d`.
- Check `docker compose ps` for `dbis_site_a` and `dbis_site_b` status.

2. Missing SQL objects or function mismatch after edits:

- Re-apply init scripts:
  - `infra/site-b-init/02_semijoin_stage.sql`
  - `infra/site-a-init/02_fdw_semijoin.sql`

3. FDW connection error from Site A to Site B:

- Confirm server name in FDW options is `site_b`.
- Confirm both containers are on same compose network.

4. Empty or inconsistent benchmark results:

- Recreate clean environment with `docker compose down -v` then `docker compose up -d`.
- Re-run `scripts/run_full_demo.ps1`.

5. Semijoin appears slower than baseline:

- This can be expected for high match-rate workloads.
- Use `scripts/selectivity_profile.sql` to show low/medium/high selectivity behavior.
- Use adaptive strategy output from `fetch_b_semijoin_auto` for report discussion.

## Notes

1. This prototype is implementation-complete at SQL/FDW usage level.
2. It does not patch PostgreSQL C internals in `postgres_fdw.c` or `deparse.c`.
3. Use this for checkpoint demo and measurable validation of semijoin data-transfer reduction.
PostgreSQL Database Management System
=====================================

This directory contains the source code distribution of the PostgreSQL
database management system.

PostgreSQL is an advanced object-relational database management system
that supports an extended subset of the SQL standard, including
transactions, foreign keys, subqueries, triggers, user-defined types
and functions.  This distribution also contains C language bindings.

Copyright and license information can be found in the file COPYRIGHT.

General documentation about this version of PostgreSQL can be found at
<https://www.postgresql.org/docs/18/>.  In particular, information
about building PostgreSQL from the source code can be found at
<https://www.postgresql.org/docs/18/installation.html>.

The latest version of this software, and related software, may be
obtained at <https://www.postgresql.org/download/>.  For more information
look at our web site located at <https://www.postgresql.org/>.
