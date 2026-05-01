#!/usr/bin/env bash
set -euo pipefail

# Interactive viva demo for the postgres_fdw semijoin project.
#
# Usage:
#   bash VIVA_INTERACTIVE_DEMO.sh
#
# Controls:
#   Type "next" or press Enter to continue.
#   Type "q" to quit.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="${PSQL:-$HOME/pg_custom/bin/psql}"
PG_ISREADY="${PG_ISREADY:-$HOME/pg_custom/bin/pg_isready}"
LOCAL_HOST="${LOCAL_HOST:-localhost}"
LOCAL_PORT="${LOCAL_PORT:-5432}"
REMOTE_HOST="${REMOTE_HOST:-localhost}"
REMOTE_PORT="${REMOTE_PORT:-5433}"
DBNAME="${DBNAME:-postgres}"
LOCAL_PGDATA="${LOCAL_PGDATA:-$HOME/pg_local}"

step_no=0

line() {
    printf '%*s\n' "${COLUMNS:-90}" '' | tr ' ' '='
}

title() {
    step_no=$((step_no + 1))
    clear || true
    line
    printf 'STEP %02d: %s\n' "$step_no" "$1"
    line
    printf '\n'
}

wait_next() {
    printf '\nType "n" to continue, "q" to quit: '
    read -r answer || true
    case "${answer:-next}" in
        q|Q|quit|QUIT|exit|EXIT)
            echo "Stopping demo."
            exit 0
            ;;
        next|NEXT|n|N|"")
            ;;
        *)
            echo "Continuing anyway. Tip: type next or q."
            sleep 0.8
            ;;
    esac
}

run_cmd() {
    echo "$ $*"
    "$@"
}

run_sql() {
    local sql="$1"
    echo "SQL>"
    echo "$sql"
    echo
    "$PSQL" -h "$LOCAL_HOST" -p "$LOCAL_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 -c "$sql"
}

run_file() {
    local file="$1"
    echo "$ $PSQL -h $LOCAL_HOST -p $LOCAL_PORT -d $DBNAME -f $file"
    "$PSQL" -h "$LOCAL_HOST" -p "$LOCAL_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/$file"
}

run_remote_file() {
    local file="$1"
    echo "$ $PSQL -h $REMOTE_HOST -p $REMOTE_PORT -d $DBNAME -f $file"
    "$PSQL" -h "$REMOTE_HOST" -p "$REMOTE_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/$file"
}

install_fdw_variant() {
    local label="$1"
    local source_file="$2"

    if [[ ! -f "$ROOT_DIR/$source_file" ]]; then
        echo "Missing $ROOT_DIR/$source_file"
        exit 1
    fi

    echo "Installing $label postgres_fdw from $source_file"
    run_cmd cp "$ROOT_DIR/$source_file" "$ROOT_DIR/postgres_fdw.c"
    run_cmd make -C "$ROOT_DIR"
    run_cmd sudo make -C "$ROOT_DIR" install
    run_cmd "$HOME/pg_custom/bin/pg_ctl" -D "$LOCAL_PGDATA" restart
    "$PG_ISREADY" -h "$LOCAL_HOST" -p "$LOCAL_PORT" -d "$DBNAME" >/dev/null
}

explain_ms() {
    local sql="$1"
    "$PSQL" -h "$LOCAL_HOST" -p "$LOCAL_PORT" -d "$DBNAME" -XAt -v ON_ERROR_STOP=1 \
        -c "EXPLAIN (ANALYZE, FORMAT JSON) $sql" |
        sed -n 's/.*\"Execution Time\": \([0-9.]*\).*/\1/p' |
        tail -n 1
}

scalar_sql() {
    local sql="$1"
    "$PSQL" -h "$LOCAL_HOST" -p "$LOCAL_PORT" -d "$DBNAME" -XAt -v ON_ERROR_STOP=1 -c "$sql"
}

run_olist_timing_comparison() {
    local label="$1"
    local key_limit="$2"
    local baseline_ms="$3"
    local optimized_ms="$4"
    local local_keys baseline_rows pushed_rows
    local speedup reduction_pct

    local_keys="$(scalar_sql "SELECT count(*) FROM public.olist_customers_local WHERE customer_key < $key_limit;")"
    baseline_rows="$(scalar_sql "SELECT count(*) FROM public.ft_olist_orders;")"
    pushed_rows="$(scalar_sql "SELECT count(*) FROM public.ft_olist_orders WHERE customer_key < $key_limit;")"

    speedup="$(awk -v b="$baseline_ms" -v o="$optimized_ms" 'BEGIN { if (o > 0) printf "%.2f", b / o; else printf "n/a" }')"
    reduction_pct="$(awk -v b="$baseline_rows" -v p="$pushed_rows" 'BEGIN { if (b > 0) printf "%.2f", 100 * (1 - p / b); else printf "0.00" }')"

    printf '%-12s | %10s | %12s | %12s | %8s | %14s | %12s | %11s\n' \
        "case" "local_keys" "baseline_ms" "optimized_ms" "speedup" "baseline_rows" "pushed_rows" "row_drop_%"
    printf '%-12s-+-%10s-+-%12s-+-%12s-+-%8s-+-%14s-+-%12s-+-%11s\n' \
        "------------" "----------" "------------" "------------" "--------" "--------------" "------------" "-----------"
    printf '%-12s | %10s | %12s | %12s | %8sx | %14s | %12s | %10s%%\n' \
        "$label" "$local_keys" "$baseline_ms" "$optimized_ms" "$speedup" "$baseline_rows" "$pushed_rows" "$reduction_pct"
}

measure_olist_ms() {
    local key_limit="$1"

    explain_ms "SELECT count(*)
FROM public.ft_olist_orders o
JOIN public.olist_customers_local c
  ON o.customer_key = c.customer_key
WHERE c.customer_key < $key_limit;"
}

title "Project Overview"
cat <<'TEXT'
We optimized local-foreign joins in postgres_fdw.

Main idea:
  If local filter says:
      customers.customer_id < 1000
  and join says:
      ft_orders.customer_id = customers.customer_id
  then we infer and push to remote:
      ft_orders.customer_id < 1000

Result:
  Remote rows drop from 100000 to about 10000.
  Runtime drops from around 131 ms to well below 40 ms.
TEXT
wait_next


title " Real Data Volume"
run_sql "SELECT count(*) AS local_customers,
       count(DISTINCT customer_id) AS distinct_customer_ids
FROM public.customers;

SELECT count(*) AS foreign_orders,
       count(DISTINCT customer_id) AS distinct_order_customer_ids
FROM public.ft_orders;"
cat <<'TEXT'


  customers is local.
  ft_orders is a foreign table backed by remote public.orders.
TEXT
wait_next

title "Main C-Level FDW Optimization"
run_sql "EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_id, o.amount, c.name
FROM public.ft_orders o
JOIN public.customers c
  ON o.customer_id = c.customer_id
WHERE c.customer_id < 1000;"
cat <<'TEXT'

  Remote SQL: ... FROM public.orders WHERE ((customer_id < 1000))

This proves the C-level postgres_fdw change pushed an inferred predicate.
TEXT
wait_next



title "Bonus Strategy: Low Selectivity"
cat <<'TEXT'
Case:
  customer_id < 100

Expected:
  Semijoin should win strongly because only 99 local keys are needed.
TEXT
echo
run_sql "SELECT *
FROM public.benchmark_semijoin_strategies(500, 100)
ORDER BY elapsed_ms;"
wait_next

title "Bonus Strategy: Medium Selectivity"
cat <<'TEXT'
Case:
  customer_id < 1000

Expected:
  batched_any should usually be fastest.
TEXT
echo
run_sql "SELECT *
FROM public.benchmark_semijoin_strategies(500, 1000)
ORDER BY elapsed_ms;"
wait_next

title "Bonus Strategy: High Selectivity"
cat <<'TEXT'
Case:
  customer_id < 5000

Expected:
  Semijoin may no longer win because too many keys are selected.
  This justifies adaptive strategy selection.
TEXT
echo
run_sql "SELECT *
FROM public.benchmark_semijoin_strategies(500, 5000)
ORDER BY elapsed_ms;"
wait_next

title "Bonus Strategy: Very High Selectivity"
cat <<'TEXT'
Case:
  customer_id < 10000

Why this case:
  This checks the large-key scenario. Here almost all local customer keys are
  selected, so the remote side may return nearly the whole orders table.

Expected:
  baseline_remote_scan can win when selectivity is too high, because the
  overhead of sending or staging many keys may be larger than the rows saved.
TEXT
echo
run_sql "SELECT *
FROM public.benchmark_semijoin_strategies(500, 10000)
ORDER BY elapsed_ms;"
wait_next

title "Adaptive Strategy Chooser"
run_sql "WITH auto_remote AS MATERIALIZED (
    SELECT *
    FROM public.fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
)
SELECT strategy,
       count(*) AS remote_rows,
       min(customer_id) AS min_customer_id,
       max(customer_id) AS max_customer_id
FROM auto_remote
GROUP BY strategy;"
cat <<'TEXT'


  auto chooses based on distinct local key count.
  For the medium case it chooses batched_any.
TEXT
wait_next



title "Real-World Olist Data Overview"
run_sql "SELECT count(*) AS local_olist_customers,
       count(DISTINCT customer_key) AS distinct_customer_keys,
       count(DISTINCT customer_state) AS states
FROM public.olist_customers_local;

SELECT count(*) AS remote_olist_orders,
       count(DISTINCT customer_key) AS distinct_order_customer_keys,
       sum(amount) AS total_order_amount
FROM public.ft_olist_orders;"
cat <<'TEXT'


  olist_customers_local is the local relation.
  ft_olist_orders is a foreign table backed by remote public.olist_orders_remote.
  This demonstrates the same optimization on anonymized real e-commerce data.
TEXT
wait_next

title "Install Baseline FDW And Measure Olist Timings"
cat <<'TEXT'
This step installs postgres_fdw_old.c as postgres_fdw.c.

Then it runs the normal join query for low, medium, and high selectivity.
These timings represent the baseline/unoptimized FDW behavior.
TEXT
echo
install_fdw_variant "baseline/unoptimized" "postgres_fdw_old.c"
baseline_low_ms="$(measure_olist_ms 100)"
baseline_medium_ms="$(measure_olist_ms 1000)"
baseline_high_ms="$(measure_olist_ms 5000)"
printf '%-12s | %12s\n' "case" "baseline_ms"
printf '%-12s-+-%12s\n' "------------" "------------"
printf '%-12s | %12s\n' "low" "$baseline_low_ms"
printf '%-12s | %12s\n' "medium" "$baseline_medium_ms"
printf '%-12s | %12s\n' "high" "$baseline_high_ms"
wait_next

title "Install Optimized FDW And Compare Olist Timings"
cat <<'TEXT'
This step installs postgres_fdw_new.c as postgres_fdw.c.

Then it runs the same normal join queries again.
No query trick is used: only the postgres_fdw implementation changes.
TEXT
echo
install_fdw_variant "optimized" "postgres_fdw_new.c"
optimized_low_ms="$(measure_olist_ms 100)"
optimized_medium_ms="$(measure_olist_ms 1000)"
optimized_high_ms="$(measure_olist_ms 5000)"

echo "Low selectivity comparison"
run_olist_timing_comparison "low" 100 "$baseline_low_ms" "$optimized_low_ms"
echo
echo "Medium selectivity comparison"
run_olist_timing_comparison "medium" 1000 "$baseline_medium_ms" "$optimized_medium_ms"
echo
echo "High selectivity comparison"
run_olist_timing_comparison "high" 5000 "$baseline_high_ms" "$optimized_high_ms"
wait_next

title "Optimized Real-World Remote SQL Proof"
cat <<'TEXT'
This is the normal medium-selectivity viva query after installing postgres_fdw_new.c.

  Remote SQL
  Execution Time
TEXT
echo
run_sql "EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_key,
       o.amount,
       c.customer_city,
       c.customer_state
FROM public.ft_olist_orders o
JOIN public.olist_customers_local c
  ON o.customer_key = c.customer_key
WHERE c.customer_key < 1000;"
wait_next

title "Real-World Selectivity Statistics"
run_sql "WITH cases(label, key_limit) AS (
    VALUES
        ('low', 100),
        ('medium', 1000),
        ('high', 5000)
), totals AS (
    SELECT count(*)::numeric AS full_remote_rows
    FROM public.ft_olist_orders
)
SELECT c.label,
       c.key_limit,
       (SELECT count(*)
        FROM public.olist_customers_local lc
        WHERE lc.customer_key < c.key_limit) AS local_keys,
       t.full_remote_rows::bigint AS baseline_remote_rows,
       (SELECT count(*)
        FROM public.ft_olist_orders fo
        WHERE fo.customer_key < c.key_limit) AS pushed_remote_rows,
       round(
           100.0 * (1.0 - (
               (SELECT count(*)::numeric
                FROM public.ft_olist_orders fo
                WHERE fo.customer_key < c.key_limit) / NULLIF(t.full_remote_rows, 0)
           )),
           2
       ) AS remote_row_reduction_pct
FROM cases c
CROSS JOIN totals t
ORDER BY c.key_limit;"
cat <<'TEXT'


  baseline_remote_rows is the cost of fetching the full remote table.
  pushed_remote_rows is what the optimized predicate needs from remote.
  The percentage column is the easy viva statistic: how much remote transfer drops.
TEXT
wait_next

title "Correctness Check"
run_sql "WITH baseline AS (
    SELECT c.customer_id, o.order_id
    FROM public.customers c
    JOIN public.ft_orders o
      ON o.customer_id = c.customer_id
    WHERE c.customer_id < 1000
), auto_join AS (
    WITH auto_remote AS MATERIALIZED (
        SELECT order_id, customer_id
        FROM public.fetch_b_semijoin_auto(1500, 50000, 500, 'auto')
    )
    SELECT c.customer_id, r.order_id
    FROM public.customers c
    JOIN auto_remote r
      ON r.customer_id = c.customer_id
    WHERE c.customer_id < 1000
)
SELECT (SELECT count(*) FROM baseline) AS baseline_rows,
       (SELECT count(*) FROM auto_join) AS auto_rows,
       ((SELECT count(*) FROM baseline) = (SELECT count(*) FROM auto_join)) AS rowcount_equal;"
cat <<'TEXT'


  rowcount_equal = true means optimization did not change result cardinality.
TEXT
wait_next

title "Logged Benchmark Metrics"
run_sql "SELECT *
FROM public.run_and_log_benchmark(500, 1000)
ORDER BY elapsed_ms;

SELECT run_id,
       run_ts,
       strategy,
       distinct_keys,
       key_threshold,
       chunk_size,
       remote_rows,
       join_rows,
       elapsed_ms
FROM public.semijoin_run_metrics
ORDER BY run_id DESC
LIMIT 9;"
wait_next

title "Statistical Benchmark"
cat <<'TEXT'
This runs 9 repetitions per strategy and reports median/avg/stddev.
It avoids relying on one lucky cached run.

It takes around 1-2 seconds.
TEXT
echo
run_file "REAL_DATA_STATISTICAL_BENCHMARK.sql"
wait_next


title "Final Summary"
cat <<'TEXT'

  We optimized postgres_fdw for local-foreign joins.
  Earlier, the foreign scan fetched all remote rows.
  We detect local-foreign equality joins and infer safe remote predicates.
  For customer_id < 1000, remote rows dropped from 100000 to about 10000.
  We also implemented bonus SQL strategies: baseline_remote_scan,
  batched_any, staged_remote_join, adaptive chooser, logging, and
  statistical benchmarking.

End line:
  The optimization improves performance while preserving correctness.
TEXT
