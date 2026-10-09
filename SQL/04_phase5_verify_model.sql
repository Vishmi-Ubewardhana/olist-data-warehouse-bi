/* =====================================================================
   PHASE 4/5 - VERIFICATION QUERIES (take screenshots for the report)
   ===================================================================== */
USE OlistDW;
GO

-- V1. Tables per schema ----------------------------------------------------
SELECT s.name AS schema_name, t.name AS table_name
FROM   sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE  s.name IN ('dw','etl','stg','mart')
ORDER  BY s.name, t.name;

-- V2. Columns, types and nullability of the warehouse tables ----------------
SELECT TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH AS max_len, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dw'
ORDER  BY TABLE_NAME, ORDINAL_POSITION;

-- V3. Primary keys ---------------------------------------------------------------
SELECT tc.TABLE_NAME, kcu.COLUMN_NAME AS primary_key_column
FROM   INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN   INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
       ON kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME AND kcu.TABLE_SCHEMA = tc.TABLE_SCHEMA
WHERE  tc.TABLE_SCHEMA = 'dw' AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
ORDER  BY tc.TABLE_NAME;

-- V4. Foreign keys = the relationships of the star schema -----------------------
SELECT  OBJECT_NAME(fk.parent_object_id)     AS fact_or_child_table,
        COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS foreign_key_column,
        OBJECT_NAME(fk.referenced_object_id) AS dimension_or_parent_table,
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS referenced_column
FROM    sys.foreign_keys fk
JOIN    sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
WHERE   SCHEMA_NAME(fk.schema_id) = 'dw'
ORDER   BY fact_or_child_table, foreign_key_column;

-- V5. Row counts (dim_date = 1,096; everything else 0 until Phase 7/8) ----------
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dw.dim_date
UNION ALL SELECT 'dim_location',     COUNT(*) FROM dw.dim_location
UNION ALL SELECT 'dim_customer',     COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'dim_seller',       COUNT(*) FROM dw.dim_seller
UNION ALL SELECT 'dim_product',      COUNT(*) FROM dw.dim_product
UNION ALL SELECT 'dim_payment_type', COUNT(*) FROM dw.dim_payment_type
UNION ALL SELECT 'dim_order_status', COUNT(*) FROM dw.dim_order_status
UNION ALL SELECT 'fact_sales',       COUNT(*) FROM dw.fact_sales
UNION ALL SELECT 'fact_payments',    COUNT(*) FROM dw.fact_payments
UNION ALL SELECT 'fact_reviews',     COUNT(*) FROM dw.fact_reviews;

-- V6. Date hierarchy check (Year > Quarter > Month) -------------------------------
SELECT year_number, quarter_number, month_number, month_name, COUNT(*) AS days_in_month
FROM   dw.dim_date
GROUP  BY year_number, quarter_number, month_number, month_name
ORDER  BY year_number, month_number;

-- V7. Template of a star join (returns rows after Phase 8) -----------------------
SELECT  d.year_number, p.category_name_en, l.region,
        SUM(f.item_total) AS revenue, COUNT(DISTINCT f.order_id) AS orders
FROM    dw.fact_sales   f
JOIN    dw.dim_date     d ON d.date_key     = f.date_key
JOIN    dw.dim_product  p ON p.product_key  = f.product_key
JOIN    dw.dim_customer c ON c.customer_key = f.customer_key
LEFT JOIN dw.dim_location l ON l.location_key = c.location_key
GROUP   BY d.year_number, p.category_name_en, l.region
ORDER   BY d.year_number, revenue DESC;
GO
