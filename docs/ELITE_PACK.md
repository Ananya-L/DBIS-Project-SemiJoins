# Elite Pack

This is the highest-value layer of the semijoin project. It combines correctness, performance science, robustness, and presentation polish.

## Components

1. Premium analytics
- `scripts/confidence_intervals.sql`
- `scripts/experiment_sweep.sql`
- `scripts/performance_trend.sql`
- `scripts/anomaly_detection.sql`
- `scripts/regression_guard.sql`

2. Visual and showcase layer
- `scripts/export_visuals.ps1`
- `scripts/best_showcase.ps1`
- `dashboard/index.html`

3. Live orchestration
- `scripts/live_demo_assistant.ps1`
- `scripts/judge_rehearsal.ps1`
- `scripts/elite_suite.ps1`

4. Submission readiness
- `scripts/create_submission_bundle.ps1`
- `scripts/run_full_demo.ps1`
- `scripts/run_addons_suite.ps1`
- `scripts/reset_reproducible_state.ps1`

## Why this is the best version

1. It does not rely on a single benchmark result.
2. It reports confidence intervals, trend, and anomaly checks.
3. It supports a polished live demo path and a final submission bundle.
4. It gives a strong viva story: correctness, tuning, robustness, and reproducibility.

## Run

powershell -ExecutionPolicy Bypass -File scripts/elite_suite.ps1
