# Submission Checklist

## A. Environment

1. Docker Desktop running.
2. `docker compose up -d` succeeds.
3. Both containers are healthy in `docker compose ps`.

## B. Core Correctness

1. Run `scripts/benchmark.sql`.
2. Confirm `rowcount_equal = t`.
3. Save output screenshot/log.

## C. Bonus Features

1. Run `scripts/bonus_benchmark.sql`.
2. Confirm auto strategy correctness (`rowcount_equal = t`).
3. Confirm `semijoin_run_metrics` receives rows.

## D. Selectivity and Statistics

1. Run `scripts/selectivity_profile.sql`.
2. Run `scripts/statistical_benchmark.sql`.
3. Record avg/p95/stddev table.

## E. Reproducibility and Fault Tests

1. Run `scripts/reset_reproducible_state.ps1`.
2. Run `scripts/run_fault_tests.ps1`.
3. Keep fault-test output as evidence.

## F. Report and Visuals

1. Run `scripts/generate_report.ps1`.
2. Run `scripts/export_visuals.ps1`.
3. Verify files in `reports/`:
- timestamped report markdown
- strategy CSV
- selectivity CSV
- chart HTML

## G. Demo Readiness

1. Run `scripts/run_full_demo.ps1` once before presentation.
2. Run `scripts/judge_mode.sql` for compact final table.
3. Prepare speaking flow from `docs/VIVA_PACK.md`.
4. Keep `docs/ARCHITECTURE.md` open during explanation.
