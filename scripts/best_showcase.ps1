$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$showcasePath = "reports/showcase_$timestamp.html"

Write-Host '=== Best Showcase Builder ==='
docker compose up -d | Out-Null

# Reuse existing generated CSVs if present; otherwise create fresh ones.
if (-not (Get-ChildItem reports -Filter 'strategy_stats_*.csv' -ErrorAction SilentlyContinue)) {
  powershell -ExecutionPolicy Bypass -File scripts/export_visuals.ps1 | Out-Null
}
if (-not (Get-ChildItem reports -Filter 'addons_summary_*.json' -ErrorAction SilentlyContinue)) {
  powershell -ExecutionPolicy Bypass -File scripts/run_addons_suite.ps1 | Out-Null
}

$strategyCsv = Get-ChildItem reports -Filter 'strategy_stats_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$selectivityCsv = Get-ChildItem reports -Filter 'selectivity_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$addonsJson = Get-ChildItem reports -Filter 'addons_summary_*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1

$summary = Get-Content $addonsJson.FullName -Raw | ConvertFrom-Json
$csvData = Import-Csv $strategyCsv.FullName
$selData = Import-Csv $selectivityCsv.FullName
$best = $csvData | Sort-Object {[double]$_.avg_ms} | Select-Object -First 1

$labels = ($csvData.strategy | ForEach-Object { "'$_'" }) -join ','
$avg = ($csvData.avg_ms | ForEach-Object { $_ }) -join ','
$p95 = ($csvData.p95_ms | ForEach-Object { $_ }) -join ','
$selLabels = ($selData.tier | ForEach-Object { "'$_'" }) -join ','
$selLocal = ($selData.local_rows | ForEach-Object { $_ }) -join ','
$selPushed = ($selData.pushed_remote_rows | ForEach-Object { $_ }) -join ','

$html = @"
<!doctype html>
<html>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1'>
  <title>Best Semijoin Showcase</title>
  <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
  <style>
    :root { --bg:#f4f8ff; --ink:#102238; --card:#fff; --accent:#0d6efd; --accent2:#25a18e; }
    body { margin:0; font-family:Segoe UI, sans-serif; background: linear-gradient(180deg,#eaf2ff 0%, var(--bg) 100%); color:var(--ink); }
    .wrap { max-width:1200px; margin:0 auto; padding:24px; }
    .hero { display:grid; grid-template-columns: repeat(auto-fit,minmax(250px,1fr)); gap:12px; margin-bottom:18px; }
    .card { background:var(--card); border-radius:16px; padding:18px; box-shadow:0 10px 30px rgba(16,34,56,.08); border:1px solid rgba(13,110,253,.08); }
    .kpi { font-size:1.8rem; font-weight:700; }
    .label { opacity:.75; font-size:.9rem; }
    .grid { display:grid; grid-template-columns: repeat(auto-fit,minmax(320px,1fr)); gap:16px; }
    canvas { max-height: 360px; }
    .muted { opacity:.75; }
    ul { margin:8px 0 0 18px; }
  </style>
</head>
<body>
<div class='wrap'>
  <div class='card'>
    <h1>Best-in-Class Semijoin Showcase</h1>
    <p class='muted'>Generated at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')</p>
  </div>
  <div class='hero'>
    <div class='card'><div class='label'>Fastest strategy</div><div class='kpi'>$($best.strategy)</div></div>
    <div class='card'><div class='label'>Avg latency (ms)</div><div class='kpi'>$($best.avg_ms)</div></div>
    <div class='card'><div class='label'>P95 latency (ms)</div><div class='kpi'>$($best.p95_ms)</div></div>
    <div class='card'><div class='label'>Auto-tune recommendation</div><div class='kpi'>$($summary.regression_guard.ok) ok / $($summary.regression_guard.regressed) regressed</div></div>
  </div>

  <div class='grid'>
    <div class='card'><canvas id='latencyChart'></canvas></div>
    <div class='card'><canvas id='selectivityChart'></canvas></div>
    <div class='card'>
      <h2>Highlights</h2>
      <ul>
        <li>Adaptive strategies with fallback and tuning history.</li>
        <li>Regression guard and anomaly detection for safety.</li>
        <li>Custom workload benchmark for targeted test cases.</li>
        <li>Statistical benchmark with confidence intervals.</li>
        <li>One-click bundle, rehearsal, and live assistant scripts.</li>
      </ul>
    </div>
  </div>
</div>
<script>
new Chart(document.getElementById('latencyChart'), {
  type: 'bar',
  data: { labels: [${labels}], datasets: [
    { label: 'avg_ms', data: [${avg}], backgroundColor: 'rgba(13,110,253,.65)' },
    { label: 'p95_ms', data: [${p95}], backgroundColor: 'rgba(37,161,142,.65)' }
  ]},
  options: { plugins: { title: { display: true, text: 'Strategy Latency' } } }
});
new Chart(document.getElementById('selectivityChart'), {
  type: 'line',
  data: { labels: [${selLabels}], datasets: [
    { label: 'local_rows', data: [${selLocal}], borderColor: '#0d6efd' },
    { label: 'pushed_remote_rows', data: [${selPushed}], borderColor: '#25a18e' }
  ]},
  options: { plugins: { title: { display: true, text: 'Selectivity Profile' } } }
});
</script>
</body>
</html>
"@

Set-Content -Path $showcasePath -Value $html -Encoding UTF8
Write-Host "Showcase generated: $showcasePath"
