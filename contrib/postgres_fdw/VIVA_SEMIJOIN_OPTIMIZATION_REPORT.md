# postgres_fdw Semijoin Optimization Report

## 1. Project Goal

The goal of this project was to optimize local-foreign joins in PostgreSQL's `postgres_fdw`.

The target query was:

```sql
SELECT o.order_id, o.amount, c.name
FROM ft_orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id < 1000;
```

Before our changes, PostgreSQL fetched all rows from the remote foreign table and then performed the join locally. This caused unnecessary network transfer and increased execution time.

## 2. Original Problem

The original execution plan looked like this:

```text
Foreign Scan on public.ft_orders o
  Remote SQL: SELECT order_id, customer_id, amount FROM public.orders
  actual rows=100000

Execution Time: 131.654 ms
```

Even though the local table had this selective condition:

```sql
c.customer_id < 1000
```

the remote query did not use it. So the foreign server sent all `100000` rows from `orders`, and PostgreSQL filtered/joined them locally.

This was inefficient because only rows matching customers below `1000` were actually needed.

## 3. Main Idea

We implemented a semijoin-style optimization.

From this join condition:

```sql
o.customer_id = c.customer_id
```

and this local filter:

```sql
c.customer_id < 1000
```

we can safely infer:

```sql
o.customer_id < 1000
```

So instead of fetching all remote rows, `postgres_fdw` now pushes an equivalent filter to the remote server:

```sql
SELECT order_id, customer_id, amount
FROM public.orders
WHERE customer_id < 1000;
```

This reduces remote rows transferred from `100000` to `10000`.

## 4. Files Modified

### `postgres_fdw.c`

Most implementation work was done here:

- Detect local-foreign join candidates.
- Infer remote predicates from local predicates.
- Add inferred predicates to the remote SQL generation path.
- Add execution metadata and EXPLAIN support.
- Add a bounded cache for repeated parameterized remote scans.

### `postgres_fdw.h`

Added planner metadata fields to `PgFdwRelationInfo`.

## 5. Important Data Structure Changes

### In `postgres_fdw.h`

We added semijoin metadata:

```c
bool semijoin_eligible;
Var *semijoin_key;
Var *semijoin_local_key;
int semijoin_threshold;
```

Meaning:

- `semijoin_eligible`: whether this foreign relation can use our optimization.
- `semijoin_key`: the foreign table join key, for example `o.customer_id`.
- `semijoin_local_key`: the matching local table join key, for example `c.customer_id`.
- `semijoin_threshold`: placeholder/tuning field for future key-count limits.

### In `PgFdwScanState`

We added execution-side metadata:

```c
bool semijoin_candidate;
AttrNumber semijoin_key_attnum;
Oid semijoin_key_type;
int semijoin_batch_size;
MemoryContext semijoin_cxt;
```

We also added a bounded parameterized scan cache:

```c
bool param_cache_enabled;
bool param_cache_scan;
MemoryContext param_cache_cxt;
List *param_cache_entries;
int param_cache_hits;
int param_cache_misses;
```

The cache avoids repeated remote calls when the same parameter value is used again.

## 6. Main Functions Added or Modified

### `detect_semijoin_candidate()`

Purpose:

Detects whether a foreign table is involved in a simple local-foreign equi-join.

Example detected pattern:

```sql
foreign_table.customer_id = local_table.customer_id
```

It checks both:

- Explicit join clauses.
- Equivalence class joins created by the PostgreSQL planner.

Why needed:

PostgreSQL may represent join equalities in different planner structures. This function centralizes detection.

### `detect_semijoin_clause()`

Purpose:

Checks one join clause and confirms whether it is safe for our optimization.

It verifies:

- The join is movable to the foreign relation.
- It is not an outer-join-only clause.
- The clause is a binary operator expression.
- One side is a foreign table column.
- The other side is a local table column.
- The type is currently `INT4`.
- The operator is mergejoinable or hashjoinable.

Why this is conservative:

We only optimize simple integer equality-style joins to avoid changing query semantics.

### `build_semijoin_implied_remote_conds()`

Purpose:

This is the core optimization function.

It takes local restrictions such as:

```sql
c.customer_id < 1000
```

and builds an equivalent remote restriction:

```sql
o.customer_id < 1000
```

Then this condition is added to `remote_exprs`, which is later deparsed into remote SQL.

Why it improves performance:

It reduces rows transferred from the remote server before the local join happens.

### `postgresGetForeignPaths()`

Modified to call:

```c
detect_semijoin_candidate(root, baserel)
```

This marks the foreign relation as semijoin-eligible during planning.

### `postgresGetForeignPlan()`

Modified to append inferred remote predicates:

```c
build_semijoin_implied_remote_conds(root, foreignrel)
```

This is where the optimization becomes visible in the generated remote SQL.

We also deduplicate inferred predicates so the remote SQL does not contain repeated conditions like:

```sql
WHERE i = 123 AND i = 123
```

### `postgresExplainForeignScan()`

Modified to expose semijoin/cache information during `EXPLAIN ANALYZE`.

This helps during debugging and demo.

### Parameterized Cache Functions

We added these helper functions:

```c
build_param_cache_key()
lookup_param_cache_entry()
begin_param_cache_fill()
remember_param_cache_tuple()
finish_param_cache_fill()
reset_param_cache_fill()
```

Purpose:

If a parameterized foreign scan sees the same key again, it can reuse the previous remote result instead of sending another remote query.

This is useful for repeated local join keys.

## 7. Before and After Performance

### Before Optimization

```text
Remote SQL:
SELECT order_id, customer_id, amount FROM public.orders

Foreign rows fetched: 100000
Execution Time: 131.654 ms
```

### After Optimization

```text
Remote SQL:
SELECT order_id, customer_id, amount
FROM public.orders
WHERE ((customer_id < 1000))

Foreign rows fetched: 10000
Execution Time: 25.234 ms
```

## 8. Performance Impact

| Metric | Before | After | Impact |
|---|---:|---:|---:|
| Remote rows fetched | 100000 | 10000 | 90% reduction |
| Execution time | 131.654 ms | 25.234 ms | About 5x faster |
| Remote SQL filter | Not present | Present | Predicate pushed down |
| Target runtime | < 90 ms | 25.234 ms | Target achieved |

## 9. Demo Query

Run:

```sql
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_id, o.amount, c.name
FROM ft_orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id < 1000;
```

What to show in the demo:

```text
Remote SQL: SELECT order_id, customer_id, amount
FROM public.orders
WHERE ((customer_id < 1000))
```

This line proves that our optimization pushed the inferred filter to the remote server.

Also show:

```text
actual rows=10000
Execution Time: 25.234 ms
```

## 10. Build, Install, and Test Commands

Build:

```bash
make -s
```

Install:

```bash
make install
```

Restart PostgreSQL:

```bash
~/pg_custom/bin/pg_ctl -D ~/pg_local restart
```

Connect:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres
```

Run tests:

```bash
make -s check
```

Final test result:

```text
All postgres_fdw regression tests passed.
All isolation tests passed.
```

## 11. Viva Explanation Script

Use this explanation:

> Our project optimizes local-foreign joins in `postgres_fdw`. Earlier, when joining a local table with a foreign table, PostgreSQL fetched all remote rows and then joined locally. In our benchmark, it fetched 100000 remote rows and took around 131 ms.
>
> We implemented semijoin-style predicate inference. If the query has a join condition like `orders.customer_id = customers.customer_id` and the local table has a filter like `customers.customer_id < 1000`, we infer the equivalent remote filter `orders.customer_id < 1000`.
>
> We then add this inferred condition to the FDW's remote expressions, so the generated remote SQL contains a `WHERE` clause. This reduced remote rows from 100000 to 10000 and reduced execution time to around 25 ms.
>
> The key functions are `detect_semijoin_candidate`, `detect_semijoin_clause`, and `build_semijoin_implied_remote_conds`. We also added a bounded parameterized scan cache for repeated remote lookups.

## 12. Limitations

Current implementation is intentionally conservative:

- Supports simple one-column integer join keys.
- Focuses on safe local-foreign equi-join patterns.
- Does not implement full batched key shipping using `ANY(array)` yet.
- Avoids scanning the local executor plan inside `ForeignScan`, because that can break PostgreSQL executor semantics.

## 13. Future Work

Possible extensions:

- Support text, UUID, date, and timestamp keys.
- Support multi-column join keys.
- Add a GUC such as `semijoin_threshold_keys`.
- Add a cost model to decide when inferred predicate pushdown is beneficial.
- Implement remote temporary table or array-based batching for large key sets.
- Add more detailed EXPLAIN output for inferred predicates.

## 14. Final Result

We successfully optimized the target local-foreign join.

Final result:

```text
Execution Time: 25.234 ms
Target: less than 90 ms
Status: Achieved
```

The main reason for the improvement was pushing the inferred predicate:

```sql
customer_id < 1000
```

into the remote SQL, reducing network transfer and remote scan output.
