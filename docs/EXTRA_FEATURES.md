# Extra Features Added

## 1. Custom Workload Benchmark

File: scripts/custom_workload_benchmark.sql

Purpose:
1. Run benchmark slices by key range (`min_key`, `max_key`) and chunk size.
2. Compare baseline, pushed direct filter, and batched semijoin behavior.

## 2. Performance Trend Analytics

File: scripts/performance_trend.sql

Purpose:
1. Compare latest run versus previous run per strategy.
2. Flag trend as improved/regressed/unchanged.
3. Provide aggregate stats (avg, p95, best, worst).

## 3. Live Demo Assistant

File: scripts/live_demo_assistant.ps1

Purpose:
1. Run compact judge mode.
2. Run auto-tuner recommendation.
3. Print trend snapshot.
4. Execute a quick custom workload benchmark.

## Usage

1. powershell -ExecutionPolicy Bypass -File scripts/live_demo_assistant.ps1
2. docker exec -i dbis_site_a psql -U postgres -d site_a_db -v min_key=1 -v max_key=500 -v chunk_size=500 -f /dev/stdin < scripts/custom_workload_benchmark.sql
3. docker exec -i dbis_site_a psql -U postgres -d site_a_db -f /dev/stdin < scripts/performance_trend.sql
