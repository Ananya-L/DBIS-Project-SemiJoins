# Bonus Features Report

## Implemented bonus features

1. Multi-strategy semijoin framework:

- `batched_any` strategy with configurable batch size.
- `staged_remote_join` strategy using a remote staging table for keys.
- `baseline_remote_scan` fallback strategy.

2. Adaptive strategy chooser:

- Function: `fetch_b_semijoin_auto(key_threshold_batch, key_threshold_staged, chunk_size, mode)`
- Supports explicit mode or automatic mode based on distinct local key count.

3. Experiment logging and reproducibility:

- Function: `benchmark_semijoin_strategies(chunk_size, key_threshold)`
- Function: `run_and_log_benchmark(chunk_size, key_threshold)`
- Table: `semijoin_run_metrics`

4. Remote staging architecture:

- Remote table: `semijoin_keys_stage` (Site B)
- Foreign mapping on Site A: `semijoin_keys_stage_ft`
- Session-scoped cleanup logic in staged strategy function.

5. Selectivity profiling and demo automation:

- Script: `scripts/selectivity_profile.sql`
- Script: `scripts/run_full_demo.ps1`
- Provides low/medium/high tier comparison and one-command execution.

## Validation run completed

Executed scripts:

1. `infra/site-b-init/02_semijoin_stage.sql`
2. `infra/site-a-init/02_fdw_semijoin.sql`
3. `scripts/bonus_benchmark.sql`
4. `scripts/selectivity_profile.sql`

Observed benchmark output:

1. `baseline_remote_scan`: remote_rows=200000, join_rows=900000, elapsed_ms=499.968
2. `batched_any`: remote_rows=180000, join_rows=900000, elapsed_ms=1778.596
3. `staged_remote_join`: remote_rows=180000, join_rows=900000, elapsed_ms=1816.158

Correctness check:

- baseline_rows=900000
- auto_rows=900000
- rowcount_equal=true

## Why this improves project quality

1. Demonstrates multiple execution strategies, not a single hardcoded approach.
2. Adds adaptive behavior and fallback, aligned with real optimizer decisions.
3. Provides experiment logging for report reproducibility.
4. Includes robust cleanup and error handling for staged key approach.
