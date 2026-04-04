# Risk Register

## R1. High match-rate workload reduces semijoin benefit

Impact: Medium
Likelihood: High

Description:
When most local keys match many remote rows, semijoin filtering may not reduce enough remote data to beat baseline scan overhead.

Mitigation:
1. Use adaptive selector with calibrated thresholds.
2. Present selectivity-profile evidence and strategy tradeoff clearly.

## R2. Network or remote-node instability during demo

Impact: High
Likelihood: Medium

Description:
FDW queries depend on Site B availability and credentials.

Mitigation:
1. Run reproducibility reset before demo.
2. Keep fault-test script output as recovery proof.
3. Have quick recovery command ready: docker restart dbis_site_b.

## R3. Non-deterministic benchmark timings

Impact: Medium
Likelihood: Medium

Description:
Single-run timing can vary due to system load and container scheduling.

Mitigation:
1. Use multi-run statistical benchmark.
2. Report avg and p95, not just one run.

## R4. Data drift from repeated manual initialization

Impact: Medium
Likelihood: Medium

Description:
Running seed SQL repeatedly can inflate row counts and skew results.

Mitigation:
1. Use reset_reproducible_state script with docker compose down -v.
2. Validate expected row counts before benchmark.

## R5. Evaluation machine differences

Impact: Medium
Likelihood: High

Description:
Different host CPU, memory, and Docker setup can change absolute latency.

Mitigation:
1. Emphasize relative strategy behavior, correctness, and reproducibility.
2. Include environment notes in generated report.
