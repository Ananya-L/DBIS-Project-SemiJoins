# Demo Command Cheat Sheet

## 1. Clean reset

Run:

powershell -ExecutionPolicy Bypass -File scripts/reset_reproducible_state.ps1

Expected:
- a_rows = 50000
- b_rows = 200000

## 2. One-command full run

Run:

powershell -ExecutionPolicy Bypass -File scripts/run_full_demo.ps1

Expected:
- core correctness rowcount_equal = t
- bonus correctness rowcount_equal = t

## 3. Judge compact output

Run:

docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/judge_mode.sql

Expected:
- RESULT row with PASS
- strategy ranking table

## 4. Auto tuning

Run:

docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/auto_tune.sql

Expected:
- one recommendation row with thresholds
- tuning history table updates

## 5. Fault test proof

Run:

powershell -ExecutionPolicy Bypass -File scripts/run_fault_tests.ps1

Expected:
- PASS baseline connectivity
- PASS restart recovery
- PASS wrong-credential detection and restore

## 6. Report + visuals

Run:

powershell -ExecutionPolicy Bypass -File scripts/generate_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/export_visuals.ps1

Expected:
- new markdown report in reports/
- strategy CSV, selectivity CSV, and chart HTML in reports/

## 7. Final bundle

Run:

powershell -ExecutionPolicy Bypass -File scripts/create_submission_bundle.ps1

Expected:
- submission_bundle_<timestamp>.zip
