#!/usr/bin/env bash
set -euo pipefail

# Download and load the real anonymized Olist e-commerce dataset for the
# postgres_fdw semijoin viva demo.
#
# This creates:
#   local  5432: olist_customers_local
#   remote 5433: olist_orders_remote
#   local  5432: ft_olist_orders -> remote olist_orders_remote
#
# We use an integer surrogate customer_key for the join because the current
# C-level postgres_fdw optimization is intentionally limited to INT4 join keys.
# The original Olist text customer IDs/cities/states/order IDs remain present.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="${PSQL:-$HOME/pg_custom/bin/psql}"
DATA_DIR="${OLIST_DATA_DIR:-/tmp/olist_real_data}"
LOCAL_PORT="${LOCAL_PORT:-5432}"
REMOTE_PORT="${REMOTE_PORT:-5433}"
DBNAME="${DBNAME:-postgres}"
BASE_URL="https://raw.githubusercontent.com/Athospd/work-at-olist-data/master/datasets"

mkdir -p "$DATA_DIR"

download_if_missing() {
    local file="$1"
    local url="$BASE_URL/$file"
    if [[ ! -s "$DATA_DIR/$file" ]]; then
        echo "Downloading $file"
        curl -L "$url" -o "$DATA_DIR/$file"
    else
        echo "Using existing $DATA_DIR/$file"
    fi
}

download_if_missing "olist_customers_dataset.csv"
download_if_missing "olist_orders_dataset.csv"
download_if_missing "olist_order_items_dataset.csv"

echo "Loading remote Olist orders on port $REMOTE_PORT"
"$PSQL" -h localhost -p "$REMOTE_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS public.olist_orders_remote;
DROP TABLE IF EXISTS public.olist_orders_raw;
DROP TABLE IF EXISTS public.olist_order_items_raw;

CREATE TABLE public.olist_orders_raw (
    order_id text,
    customer_id text,
    order_status text,
    order_purchase_timestamp text,
    order_approved_at text,
    order_delivered_carrier_date text,
    order_delivered_customer_date text,
    order_estimated_delivery_date text
);

CREATE TABLE public.olist_order_items_raw (
    order_id text,
    order_item_id integer,
    product_id text,
    seller_id text,
    shipping_limit_date text,
    price numeric,
    freight_value numeric
);
SQL

"$PSQL" -h localhost -p "$REMOTE_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 \
    -c "\\copy public.olist_orders_raw FROM '$DATA_DIR/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true)"

"$PSQL" -h localhost -p "$REMOTE_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 \
    -c "\\copy public.olist_order_items_raw FROM '$DATA_DIR/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true)"

"$PSQL" -h localhost -p "$REMOTE_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE public.olist_orders_remote AS
WITH customer_map AS (
    SELECT customer_id,
           row_number() OVER (ORDER BY customer_id)::integer AS customer_key
    FROM (
        SELECT DISTINCT customer_id
        FROM public.olist_orders_raw
    ) d
), item_totals AS (
    SELECT order_id,
           count(*)::integer AS item_count,
           sum(price)::integer AS amount
    FROM public.olist_order_items_raw
    GROUP BY order_id
)
SELECT row_number() OVER (ORDER BY o.order_id)::integer AS order_key,
       o.order_id,
       m.customer_key,
       o.customer_id,
       o.order_status,
       COALESCE(i.item_count, 0)::integer AS item_count,
       COALESCE(i.amount, 0)::integer AS amount
FROM public.olist_orders_raw o
JOIN customer_map m ON m.customer_id = o.customer_id
LEFT JOIN item_totals i ON i.order_id = o.order_id;

ALTER TABLE public.olist_orders_remote
    ADD PRIMARY KEY (order_key);

CREATE INDEX olist_orders_remote_customer_key_idx
    ON public.olist_orders_remote (customer_key);

ANALYZE public.olist_orders_remote;
SQL

echo "Loading local Olist customers on port $LOCAL_PORT"
"$PSQL" -h localhost -p "$LOCAL_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 <<SQL
DROP FOREIGN TABLE IF EXISTS public.ft_olist_orders;
DROP TABLE IF EXISTS public.olist_customers_local;
DROP TABLE IF EXISTS public.olist_customers_raw;

CREATE TABLE public.olist_customers_raw (
    customer_id text,
    customer_unique_id text,
    customer_zip_code_prefix integer,
    customer_city text,
    customer_state text
);
SQL

"$PSQL" -h localhost -p "$LOCAL_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 \
    -c "\\copy public.olist_customers_raw FROM '$DATA_DIR/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true)"

"$PSQL" -h localhost -p "$LOCAL_PORT" -d "$DBNAME" -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE public.olist_customers_local AS
SELECT row_number() OVER (ORDER BY customer_id)::integer AS customer_key,
       customer_id,
       customer_unique_id,
       customer_zip_code_prefix,
       customer_city,
       customer_state
FROM public.olist_customers_raw;

ALTER TABLE public.olist_customers_local
    ADD PRIMARY KEY (customer_key);

CREATE INDEX olist_customers_local_state_key_idx
    ON public.olist_customers_local (customer_state, customer_key);

CREATE FOREIGN TABLE public.ft_olist_orders (
    order_key integer,
    order_id text,
    customer_key integer,
    customer_id text,
    order_status text,
    item_count integer,
    amount integer
)
SERVER remote_server
OPTIONS (schema_name 'public', table_name 'olist_orders_remote');

ANALYZE public.olist_customers_local;
SQL

echo "Real Olist data setup complete."
echo "Run:"
echo "  $PSQL -h localhost -p $LOCAL_PORT -d $DBNAME -f $ROOT_DIR/OLIST_REAL_DATA_DEMO.sql"

