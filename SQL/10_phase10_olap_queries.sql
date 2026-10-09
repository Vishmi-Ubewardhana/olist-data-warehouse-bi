/* =====================================================================
   PHASE 10 - OLAP DESIGN AND ANALYTICAL QUERIES
   Demonstrates the four canonical OLAP operations - roll-up, drill-down,
   slice, dice - plus supporting analytical queries, all against
   mart.v_sales_performance / the star schema directly.

   Run after: 09_phase9_data_mart.sql

   CORRECTION:
   - Repeat-customer rate rewritten to avoid divide-by-zero.
   - Calculates the actual percentage of unique customers who have
     more than one customer/order record.
   ===================================================================== */

USE OlistDW;
GO

/* =====================================================================
   10.1 ROLL-UP: Year -> Quarter -> Month
   (aggregate from a finer grain to a coarser one)
   ===================================================================== */

SELECT
    purchase_year,
    SUM(item_total) AS revenue,
    COUNT(DISTINCT order_id) AS orders
FROM mart.v_sales_performance
GROUP BY purchase_year
ORDER BY purchase_year;
GO


SELECT
    purchase_year,
    purchase_quarter,
    SUM(item_total) AS revenue
FROM mart.v_sales_performance
GROUP BY purchase_year, purchase_quarter
ORDER BY purchase_year, purchase_quarter;
GO


-- Same roll-up expressed with GROUPING SETS, so one query returns both
-- the yearly and quarterly subtotal in a single result set.
SELECT
    purchase_year,
    purchase_quarter,
    SUM(item_total) AS revenue,
    GROUPING(purchase_quarter) AS is_year_subtotal
FROM mart.v_sales_performance
GROUP BY GROUPING SETS
(
    (purchase_year, purchase_quarter),
    (purchase_year)
)
ORDER BY purchase_year, is_year_subtotal, purchase_quarter;
GO


/* =====================================================================
   10.2 DRILL-DOWN: Region -> State -> City
   (navigate from a coarser grain down to a finer one)
   ===================================================================== */

SELECT
    customer_region,
    SUM(item_total) AS revenue
FROM mart.v_sales_performance
GROUP BY customer_region
ORDER BY revenue DESC;
GO


SELECT
    customer_state,
    SUM(item_total) AS revenue
FROM mart.v_sales_performance
WHERE customer_region = 'Southeast'
GROUP BY customer_state
ORDER BY revenue DESC;
GO


SELECT TOP 10
    customer_city,
    SUM(item_total) AS revenue,
    COUNT(*) AS line_items
FROM mart.v_sales_performance
WHERE customer_state = 'SP'
GROUP BY customer_city
ORDER BY revenue DESC;
GO


/* =====================================================================
   10.3 SLICE: fix one dimension member, look across the rest
   (here: Q4 2017 only, revenue by category)
   ===================================================================== */

SELECT TOP 10
    category_name_en,
    SUM(item_total) AS revenue
FROM mart.v_sales_performance
WHERE purchase_year = 2017
  AND purchase_quarter = 4
GROUP BY category_name_en
ORDER BY revenue DESC;
GO


/* =====================================================================
   10.4 DICE: fix a range/subset on two or more dimensions at once
   (here: the top-5 categories, broken down by region)
   ===================================================================== */

;WITH top_categories AS
(
    SELECT TOP 5
        category_name_en
    FROM mart.v_sales_performance
    GROUP BY category_name_en
    ORDER BY SUM(item_total) DESC
)
SELECT
    v.category_name_en,
    v.customer_region,
    SUM(v.item_total) AS revenue
FROM mart.v_sales_performance AS v
INNER JOIN top_categories AS t
    ON t.category_name_en = v.category_name_en
GROUP BY
    v.category_name_en,
    v.customer_region
ORDER BY
    v.category_name_en,
    revenue DESC;
GO


/* =====================================================================
   10.5 Supporting analytical queries
   ===================================================================== */

-- Top 10 sellers by revenue -------------------------------------------------

SELECT TOP 10
    s.seller_id,
    s.seller_state,
    SUM(fs.item_total) AS revenue,
    COUNT(*) AS items_sold
FROM dw.fact_sales AS fs
INNER JOIN dw.dim_seller AS s
    ON s.seller_key = fs.seller_key
GROUP BY
    s.seller_id,
    s.seller_state
ORDER BY revenue DESC;
GO


-- Delivery outcome vs. average review score ---------------------------------

SELECT
    CASE
        WHEN fs.delivery_delay_days IS NULL THEN 'not delivered'
        WHEN fs.delivery_delay_days <= 0 THEN 'on time'
        ELSE 'late'
    END AS delivery_outcome,
    AVG(CAST(fr.review_score AS DECIMAL(5,2))) AS avg_review_score,
    COUNT(*) AS n
FROM dw.fact_sales AS fs
INNER JOIN dw.fact_reviews AS fr
    ON fr.order_id = fs.order_id
GROUP BY
    CASE
        WHEN fs.delivery_delay_days IS NULL THEN 'not delivered'
        WHEN fs.delivery_delay_days <= 0 THEN 'on time'
        ELSE 'late'
    END
ORDER BY avg_review_score DESC;
GO


-- Payment-type mix (share of total payment value) ---------------------------
-- NULLIF protects the denominator if the payment fact table is empty.

;WITH payment_mix AS
(
    SELECT
        pt.payment_type,
        SUM(fp.payment_value) AS total_value,
        AVG(CAST(fp.payment_installments AS DECIMAL(10,2))) AS avg_installments
    FROM dw.fact_payments AS fp
    INNER JOIN dw.dim_payment_type AS pt
        ON pt.payment_type_key = fp.payment_type_key
    GROUP BY pt.payment_type
)
SELECT
    payment_type,
    total_value,
    CAST(
        COALESCE(
            100.0 * total_value
            / NULLIF(SUM(total_value) OVER (), 0),
            0.00
        )
        AS DECIMAL(6,2)
    ) AS pct_of_total,
    avg_installments
FROM payment_mix
ORDER BY total_value DESC;
GO


-- Repeat-customer rate -------------------------------------------------------
-- Correct definition:
-- percentage of unique customers who appear more than once.
-- NULLIF prevents divide-by-zero if dim_customer is empty.

;WITH customer_order_counts AS
(
    SELECT
        customer_unique_id,
        COUNT(*) AS order_customer_records
    FROM dw.dim_customer
    WHERE customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
),
repeat_summary AS
(
    SELECT
        COUNT(*) AS unique_people,
        SUM(
            CASE
                WHEN order_customer_records > 1 THEN 1
                ELSE 0
            END
        ) AS repeat_customers
    FROM customer_order_counts
)
SELECT
    unique_people,
    repeat_customers,
    CAST(
        COALESCE(
            100.0 * repeat_customers
            / NULLIF(unique_people, 0),
            0.00
        )
        AS DECIMAL(6,2)
    ) AS repeat_customer_rate_pct
FROM repeat_summary;
GO


/* =====================================================================
   10.6 OPTIONAL DATA AVAILABILITY CHECK
   Helps explain empty OLAP result sets.
   ===================================================================== */

SELECT
    (SELECT COUNT_BIG(*) FROM dw.dim_customer)           AS dim_customer_rows,
    (SELECT COUNT_BIG(*) FROM dw.fact_sales)             AS fact_sales_rows,
    (SELECT COUNT_BIG(*) FROM dw.fact_payments)          AS fact_payment_rows,
    (SELECT COUNT_BIG(*) FROM dw.fact_reviews)           AS fact_review_rows,
    (SELECT COUNT_BIG(*) FROM mart.v_sales_performance)  AS mart_sales_rows;
GO


PRINT 'Phase 10 complete: roll-up, drill-down, slice, dice and analytical queries executed.';
GO


USE OlistDW;
SELECT 'dim_date' AS table_name, 'dimension' AS type, COUNT(*) AS row_count FROM dw.dim_date
UNION ALL SELECT 'dim_location',     'dimension', COUNT(*) FROM dw.dim_location
UNION ALL SELECT 'dim_customer',     'dimension', COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'dim_seller',       'dimension', COUNT(*) FROM dw.dim_seller
UNION ALL SELECT 'dim_product',      'dimension', COUNT(*) FROM dw.dim_product
UNION ALL SELECT 'dim_payment_type', 'dimension', COUNT(*) FROM dw.dim_payment_type
UNION ALL SELECT 'dim_order_status', 'dimension', COUNT(*) FROM dw.dim_order_status
UNION ALL SELECT 'fact_sales',       'fact',      COUNT(*) FROM dw.fact_sales
UNION ALL SELECT 'fact_payments',    'fact',      COUNT(*) FROM dw.fact_payments
UNION ALL SELECT 'fact_reviews',     'fact',      COUNT(*) FROM dw.fact_reviews
UNION ALL SELECT 'mart.v_sales_performance', 'data mart', COUNT(*) FROM mart.v_sales_performance;

USE OlistDW;
SELECT s.name AS [schema], t.name AS [table], SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.schemas s    ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;