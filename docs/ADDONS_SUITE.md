# Addons Suite

This addon pack provides advanced observability and guardrails on top of the core semijoin project.

## Included Addons

1. Strategy matrix benchmark

- File: scripts/strategy_matrix.sql
- Compares strategies across chunk sizes and marks winners.

2. Anomaly detection

- File: scripts/anomaly_detection.sql
- Computes z-score outliers per strategy from historical run metrics.

3. Regression guard

- File: scripts/regression_guard.sql
- Flags strategies that regress beyond threshold percentage against previous run.

4. Addons orchestrator

- File: scripts/run_addons_suite.ps1
- Runs matrix, anomalies, guard checks and writes CSV+JSON outputs.

## Run

powershell -ExecutionPolicy Bypass -File scripts/run_addons_suite.ps1

## Output Artifacts

In reports/:

1. strategy*matrix*<timestamp>.csv
2. anomalies\_<timestamp>.csv
3. regression*guard*<timestamp>.csv
4. addons*summary*<timestamp>.json
