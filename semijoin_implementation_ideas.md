# Semijoin Implementation Ideas from Project Overview

Source used: [Project overview.pdf](Project%20overview.pdf)

## 1. Core Implementation Ideas

1. Add a semijoin candidate detector in planner path generation.
2. Trigger only for local-foreign equi-joins on one join key in phase 1.
3. Build distinct join keys from local side at execution time.
4. Push key filter to remote as batched predicate lists.
5. Fetch reduced remote rows and complete final join locally.

## 2. PostgreSQL Touchpoints to Modify

1. postgres_fdw.c

- Extend path generation to mark semijoin-capable foreign scans.
- Attach semijoin metadata to fdw_private for execution.

2. deparse.c

- Add SQL generation helper for dynamic key filtering.
- Support both IN (...) and = ANY(array) output paths.
- Reuse existing type output and quoting helpers.

3. Execution state

- Store key batches and semijoin flags in scan state.
- Ensure memory lifecycle is tied to per-query context.

4. explain support

- Add plan text indicating semijoin pushdown active.
- Print number of local keys and batch count for debugging.

## 3. Safer Query Shape Ideas

1. Prefer = ANY(parameterized array) where possible to limit SQL length.
2. Fall back to IN (...) literal list only when needed for compatibility.
3. Deduplicate keys before shipping to avoid repeated remote matches.
4. Skip remote fetch immediately when local key set is empty.

## 4. Cost and Fallback Ideas

1. Introduce semijoin_threshold_keys as a GUC.
2. Disable semijoin pushdown when key count exceeds threshold.
3. Add rough network cost heuristic:

- semijoin_cost = key_ship_cost + filtered_remote_scan_cost
- baseline_cost = full_remote_fetch_cost + local_join_cost

4. Use baseline plan if semijoin estimate is not better.

## 5. Batching Strategy Ideas

1. Start with default batch size 500.
2. Tune between 200 and 2000 based on latency and SQL size.
3. Track round trips and rows returned per batch for telemetry.
4. Adaptive mode idea:

- If first two batches return high match ratio, reduce batch size.
- If low match ratio, increase batch size.

## 6. Data Type Expansion Roadmap

1. Phase 1: integer keys only.
2. Phase 2: text and varchar with proper collation-safe quoting.
3. Phase 2: timestamp and date with canonical serialization.
4. Phase 3: UUID support and large key handling.

## 7. Memory and Stability Ideas

1. Build key set in a dedicated short-lived MemoryContext.
2. Reset per batch after dispatch to avoid peak memory growth.
3. Cap maximum keys processed for one scan as safety guard.
4. Add clear errors for unsupported join operators or types.

## 8. Testing Ideas

1. Functional

- Verify row equivalence with baseline local-foreign join.
- Verify zero-key local side returns zero remote fetch.

2. Planner/explain

- Confirm explain output marks semijoin path selection.
- Confirm fallback path when threshold is exceeded.

3. Performance

- Compare total bytes transferred with and without semijoin.
- Measure latency under low and high selectivity.

4. Robustness

- Test very large key sets requiring many batches.
- Test remote disconnection between batches.

## 9. Benchmark Plan Ideas

1. Use TPC-H style joins where local key cardinality varies.
2. Run three selectivity bands:

- Low match rate
- Medium match rate
- High match rate

3. Capture metrics:

- Planning time
- Execution time
- Network bytes
- Remote rows scanned
- Remote rows returned

## 10. Demo Narrative Ideas

1. Show baseline query first and explain large remote transfer.
2. Enable semijoin mode and rerun same workload.
3. Show explain output difference and transfer reduction.
4. Conclude with tradeoff:

- Semijoin wins when local key set is moderate and selective.
- Fallback remains best for massive key sets.

## 11. Stretch Ideas for Final Phase

1. Multi-column semijoin keys.
2. Bloom-filter style key summaries to cut transfer further.
3. Temporary remote staging table of keys for huge key sets.
4. Dynamic policy choosing IN, ANY(array), or temp-table strategy.

## 12. Suggested Next Build Order

1. Add planner marking and fdw_private contract.
2. Add deparse support for remote key filter SQL.
3. Add executor key extraction and batching loop.
4. Add explain annotations.
5. Add threshold fallback and tests.
6. Run benchmark suite and tune defaults.
