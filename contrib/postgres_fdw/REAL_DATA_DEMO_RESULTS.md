# Real Data Bonus Demo Results

This file summarizes the demo run on the actual local/foreign tables currently present in our PostgreSQL setup.

## 1. Data Used

Local table:

```sql
customers(customer_id, name)
```

Foreign table:

```sql
ft_orders(order_id, customer_id, amount)
```

Observed data volume:

| Table | Rows | Distinct Customer Keys |
|---|---:|---:|
| `customers` | 10000 | 10000 |
| `ft_orders` | 100000 | 10000 |

So each customer key has roughly 10 matching orders.

## 2. Demo Script

Run:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f REAL_DATA_BONUS_DEMO.sql
```

This script runs:

- C-level FDW optimization demo.
- Low, medium, and high selectivity strategy benchmarks.
- Auto strategy chooser demo.
- Forced mode comparison.
- Correctness check.
- Selectivity profile.
- Logged benchmark run.

## 3. C-Level FDW Optimization Demo

Query:

```sql
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_id, o.amount, c.name
FROM public.ft_orders o
JOIN public.customers c
  ON o.customer_id = c.customer_id
WHERE c.customer_id < 1000;
```

Important output:

```text
Remote SQL: SELECT order_id, customer_id, amount
FROM public.orders
WHERE ((customer_id < 1000))
```

Observed:

```text
Foreign Scan rows: 10000
Execution Time: 9.992 ms
```

Viva explanation:

> The FDW pushed the inferred condition `customer_id < 1000` to the remote SQL. This reduced remote rows from 100000 to 10000.

## 4. Strategy Benchmark: Low Selectivity

Condition:

```sql
customer_id < 100
```

Observed:

| Strategy | Distinct Keys | Remote Rows | Join Rows | Elapsed ms |
|---|---:|---:|---:|---:|
| `batched_any` | 99 | 990 | 990 | 7.758 |
| `staged_remote_join` | 99 | 990 | 990 | 8.273 |
| `baseline_remote_scan` | 99 | 100000 | 990 | 87.626 |

Conclusion:

Semijoin strategies are much faster because the local key set is very selective.

## 5. Strategy Benchmark: Medium Selectivity

Condition:

```sql
customer_id < 1000
```

Observed:

| Strategy | Distinct Keys | Remote Rows | Join Rows | Elapsed ms |
|---|---:|---:|---:|---:|
| `batched_any` | 999 | 9990 | 9990 | 17.683 |
| `staged_remote_join` | 999 | 9990 | 9990 | 54.333 |
| `baseline_remote_scan` | 999 | 100000 | 9990 | 95.076 |

Conclusion:

`batched_any` is best here. It fetches only 9990 remote rows instead of 100000.

## 6. Strategy Benchmark: High Selectivity

Condition:

```sql
customer_id < 5000
```

Observed:

| Strategy | Distinct Keys | Remote Rows | Join Rows | Elapsed ms |
|---|---:|---:|---:|---:|
| `baseline_remote_scan` | 4999 | 100000 | 49990 | 109.793 |
| `batched_any` | 4999 | 49990 | 49990 | 111.221 |
| `staged_remote_join` | 4999 | 49990 | 49990 | 203.358 |

Conclusion:

For high selectivity, semijoin still reduces remote rows, but batching/staging overhead can remove the benefit. This proves why an adaptive strategy chooser is useful.

## 7. Auto Strategy Chooser

Query:

```sql
SELECT *
FROM public.fetch_b_semijoin_auto(1500, 50000, 500, 'auto');
```

Observed summary:

| Strategy Chosen | Remote Rows | Min Key | Max Key |
|---|---:|---:|---:|
| `batched_any` | 9990 | 1 | 999 |

Why:

The auto chooser saw 999 local keys, which is below the batch threshold 1500, so it selected `batched_any`.

## 8. Forced Mode Comparison

Observed:

| Mode | Remote Rows |
|---|---:|
| `auto` | 9990 |
| `baseline_remote_scan` | 100000 |
| `batched_any` | 9990 |
| `staged_remote_join` | 9990 |

Explanation:

- Baseline fetches all remote rows.
- Semijoin modes fetch only matching remote rows.
- Auto selected the semijoin path.

## 9. Correctness Check

Observed:

| baseline_rows | auto_rows | rowcount_equal |
|---:|---:|---|
| 9990 | 9990 | true |

Viva explanation:

> The optimized strategy returns the same number of joined rows as the baseline, so performance improved without changing query correctness.

## 10. Selectivity Profile

Observed:

| Tier | Key Limit | Local Keys | Baseline Remote Rows | Pushed Remote Rows | Baseline ms | Pushed ms | Winner |
|---|---:|---:|---:|---:|---:|---:|---|
| low | 100 | 99 | 100000 | 990 | 49.909 | 7.154 | semijoin_win |
| medium | 1000 | 999 | 100000 | 9990 | 63.204 | 14.930 | semijoin_win |
| high | 5000 | 4999 | 100000 | 49990 | 52.667 | 69.138 | baseline_win |

Main lesson:

> Semijoin is excellent when the local key set is selective. When too many keys are selected, baseline can be better because the overhead of batching/staging becomes larger than the savings.

## 11. Logged Benchmark Run

The script stores benchmark results in:

```sql
semijoin_run_metrics
```

Latest logged medium-selectivity run:

| Strategy | Remote Rows | Join Rows | Elapsed ms |
|---|---:|---:|---:|
| `batched_any` | 9990 | 9990 | 11.749 |
| `staged_remote_join` | 9990 | 9990 | 25.881 |
| `baseline_remote_scan` | 100000 | 9990 | 88.158 |

This gives reproducible evidence for the report.

## 12. Statistical Benchmark Without One-Run Cache Bias

For report-quality numbers, we should not rely on one cached timing. We added:

```sql
REAL_DATA_STATISTICAL_BENCHMARK.sql
```

Run:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f REAL_DATA_STATISTICAL_BENCHMARK.sql
```

What it does:

- Runs 9 repetitions per strategy.
- Rotates the strategy order between runs.
- Uses a temporary table for measurements.
- Reports min, median, average, standard deviation, and max.
- Uses `DISCARD PLANS` between measurements to reduce session-level plan reuse effects.

Important note:

> SQL alone cannot fully clear PostgreSQL shared buffers or OS filesystem cache. To fully cold-cache every run, we would need server restarts and possibly OS-level cache dropping. For viva/report purposes, repeated rotated runs with median reporting are more honest than showing a single best run.

Observed statistical summary:

| Strategy | Runs | Remote Rows | Join Rows | Min ms | Median ms | Avg ms | Stddev ms | Max ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `batched_any` | 9 | 9990 | 9990 | 12.599 | 13.873 | 16.499 | 6.845 | 33.999 |
| `staged_remote_join` | 9 | 9990 | 9990 | 25.866 | 32.344 | 38.892 | 15.255 | 64.482 |
| `baseline_remote_scan` | 9 | 100000 | 9990 | 54.545 | 62.761 | 77.444 | 25.958 | 121.536 |

Correctness across all repeated runs:

| Strategy | Expected Join Rows OK | Distinct Join Row Counts |
|---|---|---:|
| `baseline_remote_scan` | true | 1 |
| `batched_any` | true | 1 |
| `staged_remote_join` | true | 1 |

Viva explanation:

> We did not depend on one cached result. We repeated each strategy 9 times, rotated execution order, and compared medians. Even statistically, `batched_any` had median 13.873 ms, while baseline median was 62.761 ms. The row counts stayed identical, so the optimization improved performance without changing correctness.

## 13. What To Say During Demo

Use this script:

> We have 10000 local customers and 100000 remote orders. The original baseline fetches all 100000 remote rows. Our C-level FDW optimization pushes the inferred predicate to the remote SQL, so only 10000 rows are fetched for `customer_id < 1000`.
>
> For the bonus part, we implemented multiple semijoin strategies. `batched_any` sends local keys in array batches, `staged_remote_join` writes keys to a remote staging table, and `baseline_remote_scan` is the fallback. The adaptive chooser selects the strategy based on distinct local key count.
>
> The low and medium selectivity cases show semijoin wins strongly. The high selectivity case shows baseline can win, which justifies having an adaptive chooser instead of always forcing semijoin.
