# monthly-city-level-metrics-report
This repository contains the SQL code necessary to generate a monthly report of key city-level metrics on order, customer and shop performance. The data used are fictitious and all SQL logic has been constructed for demonstration purposes only.

## 📜 Problem statement

Build a **report for the last closed month**, aggregated **by city**, that returns eight key metrics:

1. **Share of orders delivered in < 45 minutes**
2. **Share of stores that received no orders**
3. **Average spend (EUR)**
4. **Difference in average spend between Prime vs. non‑Prime users**
5. **Number of customers who placed their first order**
6. **% of those new customers who also ordered in their second month**
7. **Top‑1 bestselling product per store** (aggregated to city level)
8. **Average monthly orders per customer**
   
## 🗄️ Available tables
<img width="776" height="398" alt="image" src="https://github.com/user-attachments/assets/c9831432-be91-4025-96c7-3acb5622dfb1" />

## 🏗️ Query design overview

The script is split into **eight CTE blocks** (plus a parameter CTE):

1. `params` – computes `last_month_start` & `this_month_start` once.
2. `orders_under_45` – counts total orders vs. those delivered in < 45 min.
3. `stores_with_no_orders` – left‑joins stores to orders to detect inactivity.
4. `average_spend` – AVG spend overall & Prime/non‑Prime diff with `COALESCE`.
5. `first_time_customers` – identifies first‑ever orders via `ROW_NUMBER()`.
6. `customer_retention` – cohorts new sign‑ups and checks month‑2 orders.
7. `top_products` – `ROW_NUMBER()` per store ➜ `LISTAGG` per city.
8. `monthly_orders_by_customer` – counts orders per user and averages.

Finally, the **SELECT** joins all CTEs on `city`, computing percentages with `NULLIF` guards to avoid division by zero.

> See monthly_city_metrics.sql for the full, production‑ready statement.
>
