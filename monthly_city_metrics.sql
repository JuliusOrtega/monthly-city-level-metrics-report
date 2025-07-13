/* ===========================================================
   USEFUL DATE VARIABLES
   =========================================================== */
WITH params AS (
    SELECT
        DATE_TRUNC('month', CURRENT_DATE)                      AS this_month_start,
        DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month') AS last_month_start
),

/* ===========================================================
   1. Orders delivered in <45'.
   =========================================================== */
orders_under_45 AS (
    SELECT
        o.city,
        COUNT(*)                                                                AS total_orders,
        COUNT(*) FILTER (WHERE DATEDIFF(MINUTE, o.start_time, o.end_time) < 45) AS orders_under_45
    FROM
        orders o
        CROSS JOIN params p
    WHERE
        o.start_time >= p.last_month_start
        AND o.start_time <  p.this_month_start
    GROUP BY
        o.city
),

/* ===========================================================
   2. Shops without orders
   =========================================================== */
stores_with_no_orders AS (
    SELECT
        s.city,
        COUNT(*)                                            AS total_stores,
        COUNT(o.order_id) FILTER (WHERE o.order_id IS NULL) AS stores_no_orders
    FROM
        stores s
    LEFT JOIN LATERAL (
        SELECT 1 AS order_id
        FROM orders o
        CROSS JOIN params p
        WHERE o.store_id = s.id
          AND o.start_time >= p.last_month_start
          AND o.start_time <  p.this_month_start
        LIMIT 1
    ) o ON TRUE
    GROUP BY
        s.city
),

/* ================================================================
   3 & 4. Average expenditure (€) and Prime-vs-No-Prime difference
   ================================================================ */
average_spend AS (
    SELECT
        o.city,
        ROUND(AVG(o.total_cost_eur::DECIMAL(12,2)), 2)                   AS avg_spend_eur,
        ROUND(
              COALESCE(AVG(CASE WHEN c.is_prime THEN o.total_cost_eur END),0)
            - COALESCE(AVG(CASE WHEN NOT c.is_prime THEN o.total_cost_eur END),0)
        , 2)                                                             AS diff_avg_prime_nonprime
    FROM
        orders o
        JOIN customers c ON c.id = o.customer_id
        CROSS JOIN params p
    WHERE
        o.start_time >= p.last_month_start
        AND o.start_time <  p.this_month_start
    GROUP BY
        o.city
),

/* ===========================================================
   5. Customers who placed their FIRST order in the month
   =========================================================== */
first_time_customers AS (
    SELECT
        o.city,
        COUNT(DISTINCT o.customer_id) AS first_order_customers
    FROM (
        SELECT
            o.*,
            ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.start_time) AS rn
        FROM
            orders o
            CROSS JOIN params p
        WHERE
            o.start_time >= p.last_month_start
            AND o.start_time <  p.this_month_start
    ) o
    WHERE
        rn = 1
    GROUP BY
        o.city
),

/* ==================================================================
   6. % new customers (month-1 registrations) repeating in month 0
   ================================================================== */
customer_retention AS (
    SELECT
        c.preferred_city                                          AS city,
        ROUND(
            COUNT(DISTINCT CASE WHEN o2.customer_id IS NOT NULL THEN c.id END) 
            * 100.0 / COUNT(*)
        , 2) AS pct_new_customers_repeat
    FROM
        customers c
        CROSS JOIN params p
    LEFT JOIN LATERAL (
        SELECT 1 AS customer_id
        FROM orders o2
        WHERE o2.customer_id = c.id
          AND o2.start_time >= p.this_month_start
          AND o2.start_time <  p.this_month_start + INTERVAL '1 month'
        LIMIT 1
    ) o2 ON TRUE
    WHERE
        c.sign_up_time >= p.last_month_start
        AND c.sign_up_time <  p.this_month_start
    GROUP BY
        c.preferred_city
),

/* ===========================================================
   7. TOP-1 product by shop → list by city
   =========================================================== */
top_products AS (
    WITH ranked_products AS (
        SELECT
            o.store_id,
            s.city,
            op.product_id,
            ROW_NUMBER() OVER (PARTITION BY o.store_id ORDER BY COUNT(*) DESC, op.product_id) AS rn
        FROM
            order_products op
            JOIN orders  o ON o.id    = op.order_id
            JOIN stores  s ON s.id    = o.store_id
            CROSS JOIN params p
        WHERE
            o.start_time >= p.last_month_start
            AND o.start_time <  p.this_month_start
        GROUP BY
            o.store_id, s.city, op.product_id
    ),
    top_per_store AS (
        SELECT store_id, city, product_id
        FROM ranked_products
        WHERE rn = 1
    )
    SELECT
        city,
        LISTAGG(product_id, ',') WITHIN GROUP (ORDER BY product_id) AS top_products_city
    FROM
        top_per_store
    GROUP BY
        city
),

/* ===========================================================
   8. Average orders per customer (month)
   =========================================================== */
monthly_orders_by_customer AS (
    SELECT
        o.city,
        ROUND(AVG(order_count), 2) AS avg_monthly_orders
    FROM (
        SELECT
            o.customer_id,
            o.city,
            COUNT(*) AS order_count
        FROM
            orders o
            CROSS JOIN params p
        WHERE
            o.start_time >= p.last_month_start
            AND o.start_time <  p.this_month_start
        GROUP BY
            o.customer_id, o.city
    ) o
    GROUP BY
        o.city
)

/* ===========================================================
   FINAL QUERY
   =========================================================== */
SELECT
    o45.city,
    ROUND(o45.orders_under_45 * 100.0 / NULLIF(o45.total_orders,0), 2) AS pct_orders_under_45,
    ROUND(swn.stores_no_orders * 100.0 / NULLIF(swn.total_stores,0), 2) AS pct_stores_no_orders,
    aspend.avg_spend_eur,
    aspend.diff_avg_prime_nonprime,
    ftc.first_order_customers,
    cr.pct_new_customers_repeat,
    tp.top_products_city,
    mopc.avg_monthly_orders
FROM
    orders_under_45             o45
LEFT JOIN stores_with_no_orders swn   ON swn.city   = o45.city
LEFT JOIN average_spend         aspend ON aspend.city = o45.city
LEFT JOIN first_time_customers  ftc    ON ftc.city    = o45.city
LEFT JOIN customer_retention    cr     ON cr.city     = o45.city
LEFT JOIN top_products          tp     ON tp.city     = o45.city
LEFT JOIN monthly_orders_by_customer mopc ON mopc.city = o45.city
ORDER BY
    o45.city;
