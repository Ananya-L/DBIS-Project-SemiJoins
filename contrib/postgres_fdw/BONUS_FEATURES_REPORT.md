# Bonus Features Report

## Implemented Bonus Features

This bonus layer adds SQL-level semijoin execution strategies on top of the C-level `postgres_fdw` optimization already implemented in `postgres_fdw.c`.

The C optimization automatically infers and pushes predicates such as:

```sql
customers.customer_id < 1000
```

into remote SQL for `ft_orders`.

The bonus layer demonstrates additional execution strategies that can be selected, benchmarked, logged, and explained during the viva.

## Files Added

| File | Purpose |
|---|---|
| `BONUS_SITE_B_STAGE.sql` | Creates the remote staging table `semijoin_keys_stage` on the remote site. |
| `BONUS_SEMIJOIN_STRATEGIES.sql` | Defines strategy functions, adaptive chooser, staging foreign table, and metrics table. |
| `BONUS_BENCHMARK_DEMO.sql` | Runs strategy comparison, correctness check, and metrics history query. |
| `BONUS_SELECTIVITY_PROFILE.sql` | Compares baseline and semijoin behavior for low/medium/high selectivity. |
| `BONUS_RUN_FULL_DEMO.ps1` | One-command PowerShell runner for the full bonus demo. |

## Strategy Framework

### 1. `baseline_remote_scan`

Function:

```sql
fetch_b_baseline_remote_scan(key_threshold)
```

This represents the original behavior: scan the remote foreign table normally and join locally.

### 2. `batched_any`

Function:

```sql
fetch_b_semijoin_batched_any(key_threshold, chunk_size)
```

This extracts distinct local customer keys and sends them to the remote scan in batches:

```sql
WHERE customer_id = ANY(key_batch)
```

This reduces the number of remote rows returned when the local key set is selective.

### 3. `staged_remote_join`

Function:

```sql
fetch_b_semijoin_staged(key_threshold)
```

This inserts local join keys into a remote staging table:

```sql
semijoin_keys_stage
```

Then it joins `ft_orders` with the staged keys through the foreign table:

```sql
semijoin_keys_stage_ft
```

The function includes session-scoped cleanup logic and deletes staged keys even if an exception occurs.

### 4. Adaptive Strategy Chooser

Function:

```sql
fetch_b_semijoin_auto(key_threshold_batch, key_threshold_staged, chunk_size, mode)
```

Supported modes:

- `auto`
- `batched_any`
- `staged_remote_join`
- `baseline_remote_scan`

In `auto` mode, it counts distinct local keys and chooses a strategy based on thresholds.

An additional helper supports custom selectivity limits:

```sql
fetch_b_semijoin_auto_for_limit(local_key_limit, key_threshold_batch, key_threshold_staged, chunk_size, mode)
```

## Benchmarking and Logging

### Metrics Table

```sql
semijoin_run_metrics
```

Stores:

- strategy name
- distinct key count
- key threshold
- chunk size
- remote rows
- join rows
- elapsed time
- timestamp

### Benchmark Functions

```sql
benchmark_semijoin_strategies(chunk_size, key_threshold)
run_and_log_benchmark(chunk_size, key_threshold)
```

`benchmark_semijoin_strategies` compares:

- `baseline_remote_scan`
- `batched_any`
- `staged_remote_join`

`run_and_log_benchmark` runs the benchmark and stores the result in `semijoin_run_metrics`.

## Demo Commands

Run remote setup:

```bash
~/pg_custom/bin/psql -h localhost -p 5433 -d postgres -f BONUS_SITE_B_STAGE.sql
```

Run local setup:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_SEMIJOIN_STRATEGIES.sql
```

Run benchmark demo:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_BENCHMARK_DEMO.sql
```

Run selectivity profile:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_SELECTIVITY_PROFILE.sql
```

PowerShell one-command demo:

```powershell
./BONUS_RUN_FULL_DEMO.ps1
```

## Correctness Check

The benchmark demo compares row counts:

```sql
baseline_rows = auto_rows
rowcount_equal = true
```

This confirms that the optimized strategy returns the same join result cardinality as the baseline strategy.

## Validation Run Completed

Executed:

```bash
~/pg_custom/bin/psql -h localhost -p 5433 -d postgres -f BONUS_SITE_B_STAGE.sql
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_SEMIJOIN_STRATEGIES.sql
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_BENCHMARK_DEMO.sql
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f BONUS_SELECTIVITY_PROFILE.sql
```

Observed benchmark output for `key_threshold = 1000` and `chunk_size = 500`:

| Strategy | Distinct Keys | Remote Rows | Join Rows | Elapsed ms |
|---|---:|---:|---:|---:|
| `batched_any` | 999 | 9990 | 9990 | 13.010 |
| `staged_remote_join` | 999 | 9990 | 9990 | 32.993 |
| `baseline_remote_scan` | 999 | 100000 | 9990 | 55.194 |

Correctness check:

| Metric | Value |
|---|---:|
| baseline_rows | 9990 |
| auto_rows | 9990 |
| rowcount_equal | true |

Selectivity profile:

| Tier | Key Limit | Local Keys | Baseline Remote Rows | Pushed Remote Rows | Baseline ms | Pushed ms | Winner |
|---|---:|---:|---:|---:|---:|---:|---|
| low | 100 | 99 | 100000 | 990 | 50.634 | 7.101 | semijoin_win |
| medium | 1000 | 999 | 100000 | 9990 | 58.243 | 17.212 | semijoin_win |
| high | 5000 | 4999 | 100000 | 49990 | 64.300 | 98.006 | baseline_win |

Interpretation:

- Semijoin strategies are best when the local key set is selective.
- Baseline can still win for high-selectivity cases because batching overhead can exceed row-transfer savings.
- This supports the need for an adaptive strategy chooser.

## Why This Improves Project Quality

1. Shows more than one semijoin execution strategy.
2. Demonstrates adaptive strategy selection.
3. Logs experiments for reproducibility.
4. Adds a remote staging architecture for large key sets.
5. Provides selectivity profiling for low, medium, and high key counts.
6. Gives a clean viva demo beyond one hardcoded query.

## Relationship to C-Level FDW Optimization

The main C-level implementation in `postgres_fdw.c` is still the strongest result:

```text
Execution Time: about 25 ms
Remote rows: 10000 instead of 100000
```

The bonus SQL layer is a demonstration and benchmarking framework. It helps explain alternative strategies that a future FDW optimizer could choose internally.
