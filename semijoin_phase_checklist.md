# Semijoin Phase Checklist with Effort Estimates

Use this as the execution tracker for checkpoint and final demo.

## Assumptions

1. Codebase: PostgreSQL source tree with postgres_fdw.
2. Team size: 3 contributors.
3. Work unit: Engineering hours, not calendar hours.
4. Environment: 2-node setup already available or prepared in Phase 0.

## Phase 0: Environment and Baseline

Estimated effort: 8 to 12 hours

Tasks:
1. Build PostgreSQL with debug symbols.
2. Prepare Site A and Site B instances with postgres_fdw.
3. Create reproducible local and remote sample datasets.
4. Capture baseline explain analyze and runtime metrics.

Deliverables:
1. Reproducible setup notes.
2. Baseline query plans and timing table.

Exit criteria:
1. Baseline join works and is repeatable.
2. Baseline metrics captured for later comparison.

## Phase 1: Planner Marking for Semijoin Candidates

Estimated effort: 10 to 16 hours

Tasks:
1. Detect local-foreign equi-join candidates.
2. Add semijoin capability metadata to fdw_private.
3. Restrict scope to single join key and supported operators.
4. Add guardrails for unsupported cases.

Deliverables:
1. Planner path with semijoin candidate flag.
2. Explain output marker for selected semijoin candidate path.

Exit criteria:
1. Planner can distinguish semijoin-eligible and ineligible joins.
2. Explain shows when semijoin path is considered or selected.

## Phase 2: Remote SQL Deparse for Key Filtering

Estimated effort: 10 to 18 hours

Tasks:
1. Implement key-filter SQL generation in deparse path.
2. Support preferred parameterized ANY strategy.
3. Add IN-list fallback strategy.
4. Reuse existing type formatting and escaping functions.

Deliverables:
1. Deparser support for semijoin filter expression.
2. Verified SQL correctness for integer keys.

Exit criteria:
1. Remote SQL generated correctly for key batches.
2. No syntax or type errors for supported key types.

## Phase 3: Executor Key Extraction and Batched Fetch

Estimated effort: 14 to 22 hours

Tasks:
1. Extract distinct local keys during execution.
2. Batch keys with configurable batch size.
3. Execute batched remote filtered scans.
4. Assemble filtered remote tuples for local final join.

Deliverables:
1. Working semijoin execution path for integer keys.
2. Configurable batch size parameter.

Exit criteria:
1. Query result matches baseline join correctness.
2. Remote rows fetched are reduced for selective joins.

## Phase 4: Memory and Stability Hardening

Estimated effort: 8 to 14 hours

Tasks:
1. Allocate key buffers in scoped memory contexts.
2. Reset or free memory per batch.
3. Add safe limits for extreme key counts.
4. Handle empty-key fast path and remote errors.

Deliverables:
1. Stable execution under large key volumes.
2. Defensive checks and clear error messages.

Exit criteria:
1. No leaks in repeated test loops.
2. Graceful behavior for empty keys and connection failures.

## Phase 5: Cost Gate and Fallback Logic

Estimated effort: 10 to 16 hours

Tasks:
1. Add threshold based enable or disable switch.
2. Implement initial cost heuristic.
3. Compare semijoin estimate against baseline estimate.
4. Fall back to normal path when semijoin is not beneficial.

Deliverables:
1. Tunable threshold configuration.
2. Observable fallback behavior in explain.

Exit criteria:
1. Large key sets trigger fallback correctly.
2. Selected path is stable across repeated runs.

## Phase 6: Testing Suite

Estimated effort: 12 to 20 hours

Tasks:
1. Functional tests for result equivalence.
2. Explain tests for path selection and fallback.
3. Stress tests for batch counts and edge cases.
4. Negative tests for unsupported operators and datatypes.

Deliverables:
1. Automated test set with pass or fail status.
2. Test evidence for checkpoint submission.

Exit criteria:
1. All critical tests pass.
2. No correctness regressions against baseline.

## Phase 7: Benchmarking and Analysis

Estimated effort: 12 to 18 hours

Tasks:
1. Run low, medium, high selectivity workloads.
2. Record planning time and execution time.
3. Measure remote rows scanned and returned.
4. Summarize gains and non-beneficial regions.

Deliverables:
1. Performance comparison table.
2. Graphs for transfer reduction and latency.

Exit criteria:
1. Demonstrable improvement in selective scenarios.
2. Clear tradeoff statement for high-key scenarios.

## Phase 8: Demo and Documentation

Estimated effort: 6 to 10 hours

Tasks:
1. Prepare demo script with baseline and semijoin runs.
2. Capture explain snapshots and key metrics.
3. Write architecture and limitation notes.
4. Prepare fallback rationale and future roadmap.

Deliverables:
1. Final walkthrough deck or notes.
2. Submission-ready implementation summary.

Exit criteria:
1. End-to-end demo runs reliably in one attempt.
2. Team can explain design choices and tradeoffs clearly.

## Total Estimated Effort

Range: 90 to 146 engineering hours

Suggested split across 3 members:
1. Member A: planner, cost gate, explain.
2. Member B: deparse, execution batching, memory handling.
3. Member C: tests, benchmarks, docs, demo integration.

## Weekly Plan to Match Timeline

Week 1:
1. Complete Phase 0 and Phase 1.
2. Start Phase 2.

Week 2:
1. Finish Phase 2 and Phase 3.
2. Begin checkpoint demo build.

Week 3:
1. Complete Phase 4 and Phase 5.
2. Stabilize tests in Phase 6.

Week 4:
1. Run Phase 7 benchmarks.
2. Finalize Phase 8 demo package.

## Checkpoint Ready Criteria (April 6)

1. Integer-key semijoin pushdown works for local-foreign equi-join.
2. Batched key filtering to remote is visible in explain behavior.
3. Correctness validated against baseline on representative queries.
4. Initial evidence of reduced remote transfer is documented.

## Final Demo Ready Criteria (April 25)

1. Cost or threshold fallback is implemented and demonstrated.
2. Robust tests and benchmark evidence are complete.
3. Limitations and future improvements are clearly documented.
4. End-to-end demo script is reproducible on fresh setup.
