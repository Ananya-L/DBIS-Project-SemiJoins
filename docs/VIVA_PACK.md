# Viva Pack: FDW Semijoin Project

## 1. Slide Deck Outline (10 slides)

1. Problem and Motivation
- Distributed local-foreign joins over-transfer remote data.
- Goal: semijoin optimization to reduce transfer and keep correctness.

2. Baseline Architecture
- Site A: coordinator + local table `a_local`.
- Site B: remote table `b_remote`.
- Link via `postgres_fdw` foreign table `b_remote_ft`.

3. Semijoin Concept
- Send local join-key summary to remote side.
- Fetch only matching remote tuples.
- Complete final join at Site A.

4. Implemented Strategies
- `baseline_remote_scan`
- `batched_any`
- `staged_remote_join`
- `auto` strategy selector

5. System Flow
- Build key set.
- Choose strategy.
- Remote filtering.
- Local final join.
- Metrics logging.

6. Bonus Engineering
- Multi-strategy planner-like behavior.
- Threshold-based automatic fallback.
- Experiment logging table and repeated statistical benchmarking.

7. Correctness Evidence
- Rowcount equivalence checks (`rowcount_equal = t`).
- Same join result cardinalities across strategies.

8. Performance Evidence
- Core/bonus benchmark outputs.
- Statistical summary: avg/p95/stddev across rounds.
- Selectivity profile (low/medium/high keys).

9. Limitations and Tradeoffs
- High match-rate workloads can favor baseline scan.
- Strategy selection should be workload-aware.

10. Future Work
- Planner-level C patch in `postgres_fdw`.
- Multi-column key semijoins.
- Dynamic threshold calibration from historical runs.

## 2. Two-Minute Script

We built a complete two-site PostgreSQL prototype to optimize distributed joins using semijoin ideas. On Site A we keep local data, and on Site B we keep the remote relation accessed through postgres_fdw. The baseline strategy scans remote rows and joins locally. Our semijoin strategies reduce remote transfer by filtering on join keys before returning tuples.

We implemented three real strategies: batched key pushdown with ANY arrays, staged remote join using a remote key table, and an automatic selector with threshold-based fallback. We also added experiment logging and statistical benchmarking, so results are reproducible and not based on a single timing.

Correctness is validated by rowcount equality checks between baseline and semijoin paths. Performance is evaluated in core runs, bonus runs, and low-medium-high selectivity profiles. This gives a full engineering story: correctness, optimization design, adaptive behavior, and measurable evidence.

## 3. Eight-Minute Script

1. Problem context
Distributed joins are expensive because naive execution can transfer large remote relations. We target this by semijoin-inspired filtering with postgres_fdw.

2. Architecture
We run two PostgreSQL nodes in Docker. Site A has `a_local`, Site B has `b_remote`, and Site A maps Site B via FDW.

3. Baseline and semijoin strategies
Baseline scans remote and joins locally. `batched_any` sends key batches and fetches matching rows. `staged_remote_join` writes keys to remote stage and joins remotely. `auto` selects strategy by key cardinality thresholds.

4. Correctness path
For each benchmark, we compare baseline and semijoin join-cardinality outputs. All checks report equality.

5. Performance path
We run core explain benchmarks, bonus strategy comparisons, and selectivity profiling. We then run statistical benchmarking with multiple rounds and summarize avg/p95/stddev.

6. Engineering depth
We include robust cleanup, repeatable scripts, one-command full demo, and timestamped markdown report generation.

7. Key findings
Semijoin strategy wins depend on workload selectivity and overhead. Our auto selector plus evidence table provides a production-style recommendation framework.

8. Future direction
The next phase is C-level planner/deparser integration in postgres_fdw for direct optimizer-level semijoin pushdown.

## 4. Viva Q&A Quick Answers

1. Why multiple strategies?
Because one strategy is not universally best; workload selectivity and key cardinality change the best choice.

2. How did you ensure correctness?
By explicit baseline-vs-optimized rowcount equivalence checks in repeatable SQL scripts.

3. Why include p95 and stddev?
Single-run timings are noisy; statistical runs make claims defensible.

4. What is the most novel part?
Adaptive strategy selection with empirical logging and reproducible end-to-end automation.
