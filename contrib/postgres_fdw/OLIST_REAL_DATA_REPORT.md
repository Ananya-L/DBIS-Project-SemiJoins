# Olist Real Data Demo

## Why We Added This

For the viva, real anonymized data gives a stronger story than only synthetic data.

We use the Brazilian E-Commerce Public Dataset by Olist. It contains around 100k orders from 2016-2018 and includes customers, orders, order items, products, payments, reviews, and geolocation-style customer information.

## Dataset Source

Original dataset:

- Kaggle: Brazilian E-Commerce Public Dataset by Olist
- Description: 100,000 anonymized orders with order status, price, payment, freight, customer location, product attributes, and reviews.
- License on Kaggle: CC BY-NC-SA 4.0

The setup script downloads CSVs from a public GitHub mirror of the same Olist dataset:

- `olist_customers_dataset.csv`
- `olist_orders_dataset.csv`
- `olist_order_items_dataset.csv`

## Why We Use `customer_key`

The original Olist IDs are text hashes:

```text
customer_id = "06b8999e2fba1a1fbc88172c00ba8bc7"
```

Our current C-level FDW optimization is intentionally limited to integer join keys. Therefore, the loader creates an integer surrogate:

```sql
customer_key integer
```

This lets us demonstrate the FDW optimization while still using real Olist customer/order data.

## Files Added

| File | Purpose |
|---|---|
| `OLIST_REAL_DATA_SETUP.sh` | Downloads Olist CSVs and loads local/remote PostgreSQL tables. |
| `OLIST_REAL_DATA_DEMO.sql` | Runs the real Olist FDW demo and business-style queries. |
| `OLIST_REAL_DATA_REPORT.md` | Explains the real-data demo for viva. |

## Setup

Run:

```bash
cd /home/tanvi/Desktop/postgresql-18.3/contrib/postgres_fdw
chmod +x OLIST_REAL_DATA_SETUP.sh
./OLIST_REAL_DATA_SETUP.sh
```

This creates:

Local PostgreSQL, port 5432:

```sql
olist_customers_local
ft_olist_orders
```

Remote PostgreSQL, port 5433:

```sql
olist_orders_remote
```

## Demo

Run:

```bash
~/pg_custom/bin/psql -h localhost -p 5432 -d postgres -f OLIST_REAL_DATA_DEMO.sql
```

Main query:

```sql
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT o.order_key,
       o.amount,
       c.customer_city,
       c.customer_state
FROM ft_olist_orders o
JOIN olist_customers_local c
  ON o.customer_key = c.customer_key
WHERE c.customer_key < 1000;
```

Expected key point:

```text
Remote SQL includes:
WHERE ((customer_key < 1000))
```

That proves our FDW optimization works on real anonymized e-commerce data too.

## Viva Explanation

Say:

> We first validated our optimization on controlled synthetic data. Then we added a real anonymized e-commerce dataset from Olist. The original Olist IDs are text, so we created an integer surrogate key called `customer_key`, because our FDW optimization currently supports integer equi-joins. The actual customer cities, states, order IDs, order statuses, and order amounts are from the real dataset. The demo joins local Olist customers with foreign Olist orders and shows that the inferred predicate is pushed into the remote SQL.

## Why This Helps

1. Real data makes the demo more convincing.
2. We can show business-style output, such as order value by customer state.
3. We still demonstrate the same FDW optimization: reducing remote rows using inferred join-key predicates.
4. The integer surrogate key is transparent and easy to explain.

