# Submission-Ready Commands (Exact Order)

Run these commands in order before final submission/demo.

## 1. Clean deterministic reset

powershell -ExecutionPolicy Bypass -File scripts/reset_reproducible_state.ps1

## 2. Full end-to-end validation

powershell -ExecutionPolicy Bypass -File scripts/run_full_demo.ps1

## 3. Compact judge output

docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/judge_mode.sql

## 4. Fault resilience proof

powershell -ExecutionPolicy Bypass -File scripts/run_fault_tests.ps1

## 5. Auto tuning evidence

docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/auto_tune.sql

## 6. Generate report and visuals

powershell -ExecutionPolicy Bypass -File scripts/generate_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/export_visuals.ps1

## 7. Rehearsal dry run

powershell -ExecutionPolicy Bypass -File scripts/judge_rehearsal.ps1

## 8. Build final submission zip

powershell -ExecutionPolicy Bypass -File scripts/create_submission_bundle.ps1

## 9. Open key docs for viva

- docs/VIVA_PACK.md
- docs/ARCHITECTURE.md
- docs/RISK_REGISTER.md
- docs/DEMO_CHEATSHEET.md
- docs/SUBMISSION_CHECKLIST.md
