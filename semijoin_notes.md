# FDW Semijoin Optimization Notes

## Why semijoin in distributed DB

For `R(A)` at site A and `S(B)` at site B with join on key `k`:

- Naive shipping of `S` to A sends `|S|` tuples.
- Semijoin sends only projection of keys `pi_k(R)` from A to B, then B returns `S ⋉ pi_k(R)`.
- Network benefit when `|pi_k(R)|` is small relative to `|S|`, and result selectivity is good.

## Mapping this to PostgreSQL FDW

`postgres_fdw` can push selection predicates to remote servers. For mixed local-foreign joins, planner does not generally push the full join to remote if one side is local. So implement semijoin in 2 phases:

1. Build distinct local join keys at A.
2. Query foreign table at B with `WHERE key = ANY($keys)` in batches.
3. Join local table with fetched subset.

This is exactly what `fetch_b_semijoin()` in [fdw_semijoin_demo.sql](fdw_semijoin_demo.sql) does.

## Practical tuning

- Keep key batches moderate (e.g., 200 to 2000) to balance round trips and statement size.
- Ensure remote index on join key.
- Use `EXPLAIN (ANALYZE, VERBOSE)` to check remote scans are selective.
- If keys are huge, consider a staging table on site B and joining there.
