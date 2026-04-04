$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvStrategy = "reports/strategy_stats_$timestamp.csv"
$csvSelectivity = "reports/selectivity_$timestamp.csv"
$htmlChart = "reports/charts_$timestamp.html"

Write-Host 'Exporting CSV data for visuals...'
docker compose up -d | Out-Null

# Strategy stats CSV
@'
WITH runs AS (
  SELECT gs AS run_no,
         b.strategy,
         b.elapsed_ms::numeric AS elapsed_ms,
         b.remote_rows,
         b.join_rows
  FROM generate_series(1, 5) AS gs
  CROSS JOIN LATERAL benchmark_semijoin_strategies(500, 1500) AS b
)
SELECT strategy,
       round(avg(elapsed_ms),3) AS avg_ms,
       round((percentile_cont(0.95) WITHIN GROUP (ORDER BY elapsed_ms))::numeric,3) AS p95_ms,
       round(avg(remote_rows::numeric),0) AS avg_remote_rows,
       round(avg(join_rows::numeric),0) AS avg_join_rows
FROM runs
GROUP BY strategy
ORDER BY avg_ms;
'@ | docker exec -i dbis_site_a psql -U postgres -d site_a_db --csv -v ON_ERROR_STOP=1 -f - > $csvStrategy

# Selectivity CSV
@'
WITH key_freq AS (
  SELECT a.join_key, count(*) AS freq
  FROM a_local a
  GROUP BY a.join_key
), ranked AS (
  SELECT k.join_key,
         k.freq,
         ntile(3) OVER (ORDER BY k.freq ASC, k.join_key ASC) AS tier_idx
  FROM key_freq k
), picks AS (
  SELECT 'low'::text AS tier,
         ARRAY(
           SELECT r.join_key FROM ranked r WHERE r.tier_idx = 1 ORDER BY r.freq ASC, r.join_key ASC LIMIT 10
         ) AS keys
  UNION ALL
  SELECT 'medium'::text,
         ARRAY(
           SELECT r.join_key FROM ranked r WHERE r.tier_idx = 2 ORDER BY r.freq ASC, r.join_key ASC LIMIT 10
         )
  UNION ALL
  SELECT 'high'::text,
         ARRAY(
           SELECT r.join_key FROM ranked r WHERE r.tier_idx = 3 ORDER BY r.freq DESC, r.join_key ASC LIMIT 10
         )
)
SELECT p.tier,
       cardinality(p.keys) AS num_keys,
       (SELECT count(*) FROM a_local a WHERE a.join_key = ANY(p.keys)) AS local_rows,
       (SELECT count(*) FROM b_remote_ft b WHERE b.join_key = ANY(p.keys)) AS pushed_remote_rows
FROM picks p
ORDER BY CASE p.tier WHEN 'low' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END;
'@ | docker exec -i dbis_site_a psql -U postgres -d site_a_db --csv -v ON_ERROR_STOP=1 -f - > $csvSelectivity

# Build a standalone HTML chart file from CSV content.
$strategyCsv = Get-Content $csvStrategy | Select-Object -Skip 1
$labels = @()
$avg = @()
$p95 = @()
foreach ($line in $strategyCsv) {
  $parts = $line.Split(',')
  if ($parts.Count -ge 3) {
    $labels += "'" + $parts[0] + "'"
    $avg += $parts[1]
    $p95 += $parts[2]
  }
}

$html = @"
<!doctype html>
<html>
<head>
  <meta charset='utf-8'>
  <title>Semijoin Strategy Charts</title>
  <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
  <style>
    body { font-family: Segoe UI, sans-serif; margin: 24px; }
    .chart-wrap { width: 900px; max-width: 100%; margin-bottom: 30px; }
  </style>
</head>
<body>
  <h1>Semijoin Benchmark Charts</h1>
  <p>Generated at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")</p>
  <div class='chart-wrap'><canvas id='latencyChart'></canvas></div>
  <script>
    const labels = [$(($labels -join ','))];
    const avgData = [$(($avg -join ','))];
    const p95Data = [$(($p95 -join ','))];

    new Chart(document.getElementById('latencyChart'), {
      type: 'bar',
      data: {
        labels,
        datasets: [
          { label: 'avg_ms', data: avgData },
          { label: 'p95_ms', data: p95Data }
        ]
      },
      options: {
        responsive: true,
        plugins: {
          title: { display: true, text: 'Strategy Latency (avg vs p95)' }
        }
      }
    });
  </script>
</body>
</html>
"@

Set-Content -Path $htmlChart -Value $html -Encoding UTF8
Write-Host "CSV generated: $csvStrategy"
Write-Host "CSV generated: $csvSelectivity"
Write-Host "Chart HTML generated: $htmlChart"
