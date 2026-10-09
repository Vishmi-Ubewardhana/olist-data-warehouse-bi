/* =====================================================================
   PHASE 9 - DATA MART DEVELOPMENT
   Builds mart.v_sales_performance: a single, pre-joined, analysis-ready
   VIEW over the conformed EDW - the "Sales & Regional Performance"
   data mart for Sales/Category managers. It is a VIEW, not a copy, so
   it can never disagree with dw.fact_sales and always reflects the
   latest load - no separate ETL step or refresh is needed for it.
   Run after: 08_phase8_load_facts_and_validate.sql
   ===================================================================== */
USE OlistDW;
GO

DROP VIEW IF EXISTS mart.v_sales_performance;
GO

CREATE VIEW mart.v_sales_performance AS
SELECT
    fs.sales_key,
    fs.order_id,
    fs.order_item_id,
    d.full_date                              AS purchase_date,
    d.year_number                            AS purchase_year,
    d.quarter_number                         AS purchase_quarter,
    d.month_number                           AS purchase_month,
    d.month_name                             AS purchase_month_name,
    d.is_weekend,
    c.customer_state,
    lc.region                                AS customer_region,
    c.customer_city,
    p.category_name_en,
    s.seller_state,
    ls.region                                AS seller_region,
    os.order_status,
    fs.price,
    fs.freight_value,
    fs.item_total,
    fs.delivery_delay_days,
    fs.delivery_lead_time_days,
    CASE WHEN fs.delivery_delay_days IS NOT NULL
              AND fs.delivery_delay_days <= 0 THEN 1 ELSE 0 END AS on_time_delivery_flag
FROM        dw.fact_sales       fs
JOIN        dw.dim_date         d  ON d.date_key      = fs.date_key
JOIN        dw.dim_customer     c  ON c.customer_key  = fs.customer_key
LEFT JOIN   dw.dim_location     lc ON lc.location_key = c.location_key
JOIN        dw.dim_product      p  ON p.product_key   = fs.product_key
JOIN        dw.dim_seller       s  ON s.seller_key    = fs.seller_key
LEFT JOIN   dw.dim_location     ls ON ls.location_key = s.location_key
JOIN        dw.dim_order_status os ON os.order_status_key = fs.order_status_key;
GO

-- Evidence: row count must equal fact_sales (same grain, pre-joined) --------
SELECT
    (SELECT COUNT(*) FROM dw.fact_sales)            AS fact_sales_rows,
    (SELECT COUNT(*) FROM mart.v_sales_performance) AS mart_rows;
GO

-- Evidence: the view answers a typical Sales-manager question in one step,
-- with no 7-table join required by the person running it ------------------
SELECT TOP 10
    customer_region, category_name_en,
    COUNT(*)                     AS line_items,
    SUM(item_total)              AS revenue,
    AVG(delivery_delay_days)     AS avg_delivery_delay_days
FROM   mart.v_sales_performance
GROUP  BY customer_region, category_name_en
ORDER  BY revenue DESC;
GO

PRINT 'Phase 9 complete: mart.v_sales_performance created.';
GO
