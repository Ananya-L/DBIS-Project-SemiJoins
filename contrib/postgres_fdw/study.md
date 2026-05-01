# Study Notes: postgres_fdw Semijoin Optimization

## 1. One-Line Project Summary

We optimized `postgres_fdw` so that, when PostgreSQL joins a local table with a remote foreign table, it can infer safe remote-side filters from local filters and push those filters to the remote server. This reduces the number of rows fetched over the network.

Simple viva line:

```text
Earlier postgres_fdw fetched all remote rows and joined locally. Our optimization detects a local-foreign join, infers an equivalent remote predicate, and pushes it into Remote SQL so fewer remote rows are transferred.
```

## 2. The Problem

Target query:

```sql
SELECT o.order_id, o.amount, c.name
FROM public.ft_orders o
JOIN public.customers c
  ON o.customer_id = c.customer_id
WHERE c.customer_id < 1000;
```

Here:

- `customers` is local.
- `ft_orders` is a foreign table pointing to remote `orders`.
- The local filter is `c.customer_id < 1000`.
- The join condition is `o.customer_id = c.customer_id`.

Before optimization, the old `postgres_fdw.c` generated remote SQL like:

```sql
SELECT order_id, customer_id, amount
FROM public.orders;
```

That means the remote server sent all rows, for example `100000` orders, to the local server. Only after fetching those rows did PostgreSQL apply the local join/filter logic.

Why this is slow:

- Network transfer is expensive.
- The local server receives many rows it does not need.
- The join then processes unnecessary tuples.

## 3. Main Optimization Idea

From the join:

```sql
o.customer_id = c.customer_id
```

and the local filter:

```sql
c.customer_id < 1000
```

we can safely infer:

```sql
o.customer_id < 1000
```

So the optimized FDW generates remote SQL like:

```sql
SELECT order_id, customer_id, amount
FROM public.orders
WHERE customer_id < 1000;
```

This is called a semijoin-style optimization because the remote table is pre-filtered using the set/range of keys allowed by the local side.

Important phrase for viva:

```text
We are not changing the final answer. We are only reducing the remote candidate rows before the local join.
```

## 4. Why The Inference Is Correct

If:

```text
remote.customer_id = local.customer_id
```

and:

```text
local.customer_id < 1000
```

then any remote row that can successfully join must also satisfy:

```text
remote.customer_id < 1000
```

Rows with `remote.customer_id >= 1000` cannot match any local row that passes the filter. Therefore, filtering them at the remote server is safe.

This preserves correctness because:

- The join condition is equality.
- The inferred predicate uses the same join key.
- We only push predicates when the pattern is simple and safe.

## 5. What Changed In The C Code

Main files:

- `postgres_fdw.c`
- `postgres_fdw.h`

Backup/demo files:

- `postgres_fdw_old.c`: baseline/unoptimized implementation.
- `postgres_fdw_new.c`: optimized implementation.

### Metadata Added

In `PgFdwRelationInfo`, we added fields like:

```c
bool semijoin_eligible;
Var *semijoin_key;
Var *semijoin_local_key;
int semijoin_threshold;
```

Meaning:

- `semijoin_eligible`: this foreign relation has a safe local-foreign join pattern.
- `semijoin_key`: the foreign-side join key, for example `o.customer_id`.
- `semijoin_local_key`: the local-side join key, for example `c.customer_id`.
- `semijoin_threshold`: a tuning placeholder for future selectivity/key-count decisions.

In `PgFdwScanState`, we added execution-side metadata and cache fields for diagnostics and repeated parameterized scans.

## 6. Important Functions To Explain

### `detect_semijoin_candidate()`

Purpose:

Detects whether a foreign table is part of a local-foreign equality join.

Example pattern:

```sql
ft_orders.customer_id = customers.customer_id
```

This runs during planning. If it finds a safe candidate, it marks the foreign relation as semijoin eligible.

Viva wording:

```text
This function answers: is this foreign scan part of a join where a local predicate can be transferred to the remote side?
```

### `detect_semijoin_clause()`

Purpose:

Checks one join clause and confirms it is safe.

It verifies:

- The condition is a binary operator expression.
- One side is a foreign table column.
- The other side is a local table column.
- The join is equality-style.
- The key type is currently conservative, mainly integer.
- The clause is safe to use for this relation.

Viva wording:

```text
This function is deliberately conservative. If we are not sure it is safe, we do not optimize.
```

### `build_semijoin_implied_remote_conds()`

Purpose:

This is the heart of the optimization.

It looks at local restrictions like:

```sql
c.customer_id < 1000
```

and builds equivalent remote restrictions like:

```sql
o.customer_id < 1000
```

These inferred restrictions are added to the FDW remote conditions, so the deparser includes them in `Remote SQL`.

Viva wording:

```text
This function converts a local-side filter into an equivalent foreign-side filter using the equality join relationship.
```

### `postgresGetForeignPaths()`

Purpose:

Part of FDW planning. We modified it to detect semijoin opportunities early.

### `postgresGetForeignPlan()`

Purpose:

Builds the final foreign scan plan. We modified it so inferred remote predicates are appended to the remote expression list.

This is where the optimization becomes visible in `EXPLAIN` as:

```text
Remote SQL: ... WHERE ((customer_id < 1000))
```

### `postgresExplainForeignScan()`

Purpose:

Adds debug/demo visibility in `EXPLAIN ANALYZE`.

## 7. Before And After

Baseline old behavior:

```text
Remote SQL: SELECT order_id, customer_id, amount FROM public.orders
Remote rows fetched: 100000
Execution Time: around 130 ms
```

Optimized behavior:

```text
Remote SQL: SELECT order_id, customer_id, amount FROM public.orders WHERE ((customer_id < 1000))
Remote rows fetched: around 10000
Execution Time: around 25 ms, depending on cache/system state
```

Main improvement:

```text
Rows transferred over the network drop by about 90%.
```

## 8. Real-World Olist Demo

Real-world setup:

- Local table: `public.olist_customers_local`
- Remote table: `public.olist_orders_remote`
- Foreign table on local: `public.ft_olist_orders`

Main query:

```sql
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_key,
       o.amount,
       c.customer_city,
       c.customer_state
FROM public.ft_olist_orders o
JOIN public.olist_customers_local c
  ON o.customer_key = c.customer_key
WHERE c.customer_key < 1000;
```

Expected optimized proof:

```text
Remote SQL contains a WHERE condition on customer_key.
```

What to say:

```text
This proves the same optimization works not only on synthetic customers/orders but also on anonymized real e-commerce data.
```

## 9. Low, Medium, High Selectivity

Selectivity means how many local keys pass the filter.

### Low Selectivity

Example:

```sql
WHERE c.customer_key < 100
```

Only a small number of local keys qualify.

Expected result:

- Huge reduction in remote rows.
- Optimized query should win strongly.

### Medium Selectivity

Example:

```sql
WHERE c.customer_key < 1000
```

This is the main demo case.

Expected result:

- Significant remote row reduction.
- Good speedup.
- Easy to show in `Remote SQL`.

### High Selectivity

Example:

```sql
WHERE c.customer_key < 5000
```

Many local keys qualify.

Expected result:

- More remote rows are needed.
- Optimization may still help, but benefit is smaller.
- For some SQL-level strategies, baseline can win if batching overhead is high.

Viva wording:

```text
Semijoin optimization is most useful when the local side is selective. If almost all keys qualify, there are fewer rows to eliminate, so the benefit becomes smaller.
```

## 10. How Baseline Vs Optimized Demo Works

Your interactive viva script now uses actual source swapping:

Baseline:

```bash
cp postgres_fdw_old.c postgres_fdw.c
make
sudo make install
~/pg_custom/bin/pg_ctl -D ~/pg_local restart
```

Optimized:

```bash
cp postgres_fdw_new.c postgres_fdw.c
make
sudo make install
~/pg_custom/bin/pg_ctl -D ~/pg_local restart
```

Then it runs the same normal SQL query in both cases.

Important point:

```text
The query is not changed. Only the FDW implementation changes.
```

That makes the comparison strong for viva.

## 11. Bonus SQL Strategy Layer

Besides the C-level optimization, you also built SQL-level strategies to explain semijoin execution alternatives.

### `baseline_remote_scan`

Represents original behavior:

```text
Fetch remote rows normally, then join/filter locally.
```

### `batched_any`

Extracts local keys and sends them to remote in chunks:

```sql
WHERE customer_id = ANY(key_batch)
```

Why useful:

- Good for low/medium selectivity.
- Avoids fetching the full remote table.

### `staged_remote_join`

Uses a remote staging table:

```sql
public.semijoin_keys_stage
```

Flow:

1. Insert selected local join keys into a remote staging table.
2. Join remote orders with staged keys.
3. Delete staged keys using a session id.

Why useful:

- Better idea for larger key sets.
- Avoids sending a huge `ANY(array)` expression.

### Adaptive Strategy

Function:

```sql
fetch_b_semijoin_auto(...)
```

It chooses:

- `batched_any` for small key sets.
- `staged_remote_join` for larger but still useful key sets.
- `baseline_remote_scan` when too many keys qualify.

Viva wording:

```text
The adaptive strategy shows that optimization should depend on selectivity. There is no single best strategy for every query.
```

## 12. Correctness Checks

You compare baseline and optimized row counts.

Example:

```sql
WITH baseline AS (...),
     auto_join AS (...)
SELECT baseline_count,
       auto_count,
       baseline_count = auto_count AS rowcount_equal;
```

What to say:

```text
Performance improved, but result cardinality stayed the same. That confirms we did not change query semantics.
```

## 13. What To Point At During Demo

In `EXPLAIN (ANALYZE, VERBOSE, BUFFERS)`, point at:

```text
Remote SQL
```

Before:

```text
Remote SQL: SELECT ... FROM public.orders
```

After:

```text
Remote SQL: SELECT ... FROM public.orders WHERE ((customer_id < 1000))
```

Also point at:

```text
actual rows
Execution Time
```

Your explanation order:

1. This is the same SQL query.
2. In old FDW, remote SQL has no filter.
3. In new FDW, remote SQL has inferred filter.
4. Remote rows are reduced.
5. Execution time improves.
6. Row count/correctness remains same.

## 14. Common Viva Questions

### Why is this called semijoin optimization?

Because the remote side is filtered using information from the local side before performing the full join. We only ask the remote server for rows that can possibly match the local filtered keys.

### Why not always do this?

Because it is only safe for certain join patterns. It is most beneficial when the local filter is selective. If too many keys qualify, overhead may outweigh savings.

### What makes the optimization safe?

We only infer predicates across equality join keys. If `remote.key = local.key` and `local.key < X`, then any matching `remote.key` must also be `< X`.

### Does this change query results?

No. It only removes remote rows that cannot possibly join with the filtered local rows.

### What are current limitations?

- Mainly simple one-column integer keys.
- Simple equality joins.
- Conservative predicate inference.
- More types and multi-column joins are future work.

### What is the main performance bottleneck solved?

Network transfer and unnecessary remote row fetching.

### What is the strongest evidence?

The `Remote SQL` line in `EXPLAIN` and the reduction in remote rows/execution time.

## 15. Final Viva Script

Use this polished answer:

```text
In this project, we optimized postgres_fdw for local-foreign joins. Previously, when a local table was joined with a foreign table, postgres_fdw fetched all remote rows and then applied the join locally. In our example, it fetched 100000 remote rows even though the local condition customer_id < 1000 meant only around 10000 remote rows could match.

Our optimization detects a safe equality join between the local and foreign tables. From orders.customer_id = customers.customer_id and customers.customer_id < 1000, we infer orders.customer_id < 1000. We add that inferred predicate to the FDW remote conditions, so the generated Remote SQL contains a WHERE clause.

The result is that filtering happens on the remote server, remote rows transferred are reduced, and execution time improves. We verify correctness by comparing row counts between baseline and optimized queries. We also show low, medium, and high selectivity cases to explain when semijoin optimization gives maximum benefit.
```

## 16. Files To Know

- `postgres_fdw.c`: active source file compiled into PostgreSQL.
- `postgres_fdw_old.c`: baseline source used for unoptimized timing.
- `postgres_fdw_new.c`: optimized source used for optimized timing.
- `postgres_fdw.h`: metadata structure changes.
- `VIVA_INTERACTIVE_DEMO.sh`: guided viva demo script.
- `BONUS_SEMIJOIN_STRATEGIES.sql`: SQL strategy framework.
- `BONUS_SITE_B_STAGE.sql`: remote staging table setup.
- `OLIST_REAL_DATA_SETUP.sh`: Olist real-data setup.
- `OLIST_REAL_DATA_DEMO.sql`: real-data query demo.
- `VIVA_SEMIJOIN_OPTIMIZATION_REPORT.md`: formal report.

## 17. One-Minute Version

```text
The core issue was unnecessary remote row transfer. The local filter was not being used by the foreign scan, so postgres_fdw fetched the full remote table. We added planner logic to detect local-foreign equality joins and infer equivalent remote predicates. These inferred predicates are added to remote conditions and appear in Remote SQL. This reduces remote rows, improves execution time, and keeps the result unchanged. The optimization is conservative and works best for selective local filters.
```
