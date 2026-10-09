/* =====================================================================
   PHASE 8 - ETL: LOAD FACTS + WAREHOUSE VALIDATION
   Loads fact_sales, fact_payments, fact_reviews from staging, resolving
   every natural key to its dw surrogate key, then reconciles row
   counts and value sums against staging, and checks for orphan keys.

   Run after: 03 (dim_date), 06 (staging loaded), 07 (dimensions loaded).
   Safe to re-run: each fact table is cleared before it is loaded.

   CHANGES vs the previous version
     - PRE-FLIGHT check in every load step: stops with a clear message if
       dw.dim_date is not populated (1,096 rows) or a dimension is empty.
       (The FOREIGN KEY errors fk_fs_deliv_date / fk_fp_date / fk_fr_date
       mean dim_date was empty, e.g. after re-running script 02.)
     - TRY/CATCH: a failed load now writes the real error text to
       etl.load_log instead of leaving the step as 'STARTED'.
     - Identity reseed only when the table has been used (otherwise the
       first surrogate key would be 0 instead of 1).
     - Validation shows PASS/FAIL, and the final message is only
       "complete" when the counts really match.
   ===================================================================== */
USE OlistDW;
GO

/* =====================================================================
   8.1 FACT_SALES  (grain: one row per order line)
   ===================================================================== */
DECLARE @load_id INT, @rows INT;

-- PRE-FLIGHT -----------------------------------------------------------
IF (SELECT COUNT(*) FROM dw.dim_date) < 1096
    THROW 50001, 'dw.dim_date is empty or incomplete. Run 03_phase5_populate_dim_date.sql (expect 1,096 rows), then re-run this script.', 1;
IF NOT EXISTS (SELECT 1 FROM dw.dim_customer)
   OR NOT EXISTS (SELECT 1 FROM dw.dim_product)
   OR NOT EXISTS (SELECT 1 FROM dw.dim_seller)
   OR NOT EXISTS (SELECT 1 FROM dw.dim_order_status)
    THROW 50002, 'One or more dimensions are empty. Run 06 (staging) and 07 (dimensions) first.', 1;

INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Load fact_sales', 'dw.fact_sales', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

BEGIN TRY
    DELETE FROM dw.fact_sales;
    IF EXISTS (SELECT 1 FROM sys.identity_columns
               WHERE object_id = OBJECT_ID(N'dw.fact_sales') AND last_value IS NOT NULL)
        DBCC CHECKIDENT ('dw.fact_sales', RESEED, 0) WITH NO_INFOMSGS;

    ;WITH oi AS (
        SELECT order_id, TRY_CAST(order_item_id AS SMALLINT) AS order_item_id,
               product_id, seller_id,
               TRY_CAST(price AS DECIMAL(10,2))         AS price,
               TRY_CAST(freight_value AS DECIMAL(10,2))  AS freight_value
        FROM   stg.order_items
    ),
    o AS (
        SELECT order_id, customer_id, order_status,
               TRY_CAST(order_purchase_timestamp AS DATETIME2(0))      AS purchase_ts,
               TRY_CAST(order_delivered_customer_date AS DATETIME2(0)) AS delivered_ts,
               TRY_CAST(order_estimated_delivery_date AS DATETIME2(0)) AS estimated_ts
        FROM   stg.orders
    )
    INSERT INTO dw.fact_sales
        (order_id, order_item_id, date_key, delivered_date_key, estimated_date_key,
         customer_key, product_key, seller_key, order_status_key,
         price, freight_value, delivery_delay_days, delivery_lead_time_days)
    SELECT
        oi.order_id, oi.order_item_id,
        CONVERT(INT, CONVERT(CHAR(8), o.purchase_ts, 112))                                   AS date_key,
        CASE WHEN o.delivered_ts IS NULL THEN NULL
             ELSE CONVERT(INT, CONVERT(CHAR(8), o.delivered_ts, 112)) END                    AS delivered_date_key,
        CASE WHEN o.estimated_ts IS NULL THEN NULL
             ELSE CONVERT(INT, CONVERT(CHAR(8), o.estimated_ts, 112)) END                    AS estimated_date_key,
        dc.customer_key, dp.product_key, ds.seller_key, dos.order_status_key,
        oi.price, oi.freight_value,
        CASE WHEN o.delivered_ts IS NULL THEN NULL
             ELSE CAST(DATEDIFF(MINUTE, o.estimated_ts, o.delivered_ts) / 1440.0 AS DECIMAL(9,2)) END AS delivery_delay_days,
        CASE WHEN o.delivered_ts IS NULL THEN NULL
             ELSE CAST(DATEDIFF(MINUTE, o.purchase_ts, o.delivered_ts) / 1440.0 AS DECIMAL(9,2)) END  AS delivery_lead_time_days
    FROM       oi
    JOIN       o   ON o.order_id = oi.order_id
    JOIN       dw.dim_customer     dc  ON dc.customer_id   = o.customer_id
    JOIN       dw.dim_product      dp  ON dp.product_id    = oi.product_id
    JOIN       dw.dim_seller       ds  ON ds.seller_id     = oi.seller_id
    JOIN       dw.dim_order_status dos ON dos.order_status = o.order_status
    WHERE      oi.order_item_id IS NOT NULL AND o.purchase_ts IS NOT NULL;

    SET @rows = @@ROWCOUNT;
    UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
    WHERE load_id = @load_id;
END TRY
BEGIN CATCH
    UPDATE etl.load_log
    SET    finished_at = SYSDATETIME(), status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
    WHERE  load_id = @load_id;
    THROW;
END CATCH;
GO

/* =====================================================================
   8.2 FACT_PAYMENTS  (grain: one row per order payment line)
        Note: the source has no separate payment date, so the order
        purchase date is used (documented design assumption).
   ===================================================================== */
DECLARE @load_id INT, @rows INT;

-- PRE-FLIGHT -----------------------------------------------------------
IF (SELECT COUNT(*) FROM dw.dim_date) < 1096
    THROW 50001, 'dw.dim_date is empty or incomplete. Run 03_phase5_populate_dim_date.sql (expect 1,096 rows), then re-run this script.', 1;
IF NOT EXISTS (SELECT 1 FROM dw.dim_customer)
   OR NOT EXISTS (SELECT 1 FROM dw.dim_payment_type)
    THROW 50002, 'One or more dimensions are empty. Run 06 (staging) and 07 (dimensions) first.', 1;

INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Load fact_payments', 'dw.fact_payments', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

BEGIN TRY
    DELETE FROM dw.fact_payments;
    IF EXISTS (SELECT 1 FROM sys.identity_columns
               WHERE object_id = OBJECT_ID(N'dw.fact_payments') AND last_value IS NOT NULL)
        DBCC CHECKIDENT ('dw.fact_payments', RESEED, 0) WITH NO_INFOMSGS;

    INSERT INTO dw.fact_payments
        (order_id, payment_sequential, date_key, customer_key, payment_type_key,
         payment_value, payment_installments)
    SELECT
        pay.order_id,
        TRY_CAST(pay.payment_sequential AS SMALLINT),
        CONVERT(INT, CONVERT(CHAR(8), o.purchase_ts, 112)) AS date_key,
        dc.customer_key,
        dpt.payment_type_key,
        TRY_CAST(pay.payment_value AS DECIMAL(10,2)),
        TRY_CAST(pay.payment_installments AS SMALLINT)
    FROM (
        SELECT order_id, payment_sequential, payment_type, payment_installments, payment_value
        FROM   stg.order_payments
    ) pay
    JOIN (
        SELECT order_id, customer_id, TRY_CAST(order_purchase_timestamp AS DATETIME2(0)) AS purchase_ts
        FROM   stg.orders
    ) o ON o.order_id = pay.order_id
    JOIN dw.dim_customer     dc  ON dc.customer_id  = o.customer_id
    JOIN dw.dim_payment_type dpt ON dpt.payment_type = LTRIM(RTRIM(pay.payment_type))
    WHERE o.purchase_ts IS NOT NULL;

    SET @rows = @@ROWCOUNT;
    UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
    WHERE load_id = @load_id;
END TRY
BEGIN CATCH
    UPDATE etl.load_log
    SET    finished_at = SYSDATETIME(), status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
    WHERE  load_id = @load_id;
    THROW;
END CATCH;
GO

/* =====================================================================
   8.3 FACT_REVIEWS  (grain: one row per order, de-duplicated)
        Rule: some orders have more than one review; keep only the row
        with the latest review_answer_timestamp per order_id.
   ===================================================================== */
DECLARE @load_id INT, @rows INT;

-- PRE-FLIGHT -----------------------------------------------------------
IF (SELECT COUNT(*) FROM dw.dim_date) < 1096
    THROW 50001, 'dw.dim_date is empty or incomplete. Run 03_phase5_populate_dim_date.sql (expect 1,096 rows), then re-run this script.', 1;
IF NOT EXISTS (SELECT 1 FROM dw.dim_customer)
    THROW 50002, 'dw.dim_customer is empty. Run 06 (staging) and 07 (dimensions) first.', 1;

INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Load fact_reviews', 'dw.fact_reviews', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

BEGIN TRY
    DELETE FROM dw.fact_reviews;
    IF EXISTS (SELECT 1 FROM sys.identity_columns
               WHERE object_id = OBJECT_ID(N'dw.fact_reviews') AND last_value IS NOT NULL)
        DBCC CHECKIDENT ('dw.fact_reviews', RESEED, 0) WITH NO_INFOMSGS;

    ;WITH rv AS (
        SELECT  review_id, order_id,
                TRY_CAST(review_score AS TINYINT)                          AS review_score,
                review_comment_message,
                TRY_CAST(review_creation_date AS DATETIME2(0))             AS creation_ts,
                TRY_CAST(review_answer_timestamp AS DATETIME2(0))          AS answer_ts,
                ROW_NUMBER() OVER (PARTITION BY order_id
                                    ORDER BY TRY_CAST(review_answer_timestamp AS DATETIME2(0)) DESC) AS rn
        FROM    stg.order_reviews
    ),
    dedup AS (
        SELECT * FROM rv WHERE rn = 1
    )
    INSERT INTO dw.fact_reviews
        (order_id, review_id, date_key, customer_key, review_score, has_comment,
         review_answer_lead_time_days)
    SELECT
        d.order_id, d.review_id,
        CONVERT(INT, CONVERT(CHAR(8), d.creation_ts, 112)) AS date_key,
        dc.customer_key,
        d.review_score,
        CASE WHEN d.review_comment_message IS NOT NULL
                  AND LTRIM(RTRIM(d.review_comment_message)) <> '' THEN 1 ELSE 0 END AS has_comment,
        CAST(DATEDIFF(MINUTE, d.creation_ts, d.answer_ts) / 1440.0 AS DECIMAL(9,2))  AS review_answer_lead_time_days
    FROM   dedup d
    JOIN   stg.orders o ON o.order_id = d.order_id
    JOIN   dw.dim_customer dc ON dc.customer_id = o.customer_id
    WHERE  d.creation_ts IS NOT NULL AND d.review_score IS NOT NULL;

    SET @rows = @@ROWCOUNT;
    UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
    WHERE load_id = @load_id;
END TRY
BEGIN CATCH
    UPDATE etl.load_log
    SET    finished_at = SYSDATETIME(), status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
    WHERE  load_id = @load_id;
    THROW;
END CATCH;
GO

/* =====================================================================
   8.4 VALIDATION - row-count reconciliation vs staging
   ===================================================================== */
SELECT check_name, staging_count, dw_count,
       CASE WHEN staging_count = dw_count THEN 'PASS' ELSE 'FAIL' END AS validation_status
FROM (
    SELECT 'order_items -> fact_sales' AS check_name,
           (SELECT COUNT(*) FROM stg.order_items) AS staging_count,
           (SELECT COUNT(*) FROM dw.fact_sales)   AS dw_count
    UNION ALL
    SELECT 'order_payments -> fact_payments',
           (SELECT COUNT(*) FROM stg.order_payments),
           (SELECT COUNT(*) FROM dw.fact_payments)
    UNION ALL
    SELECT 'distinct reviewed orders -> fact_reviews',
           (SELECT COUNT(DISTINCT order_id) FROM stg.order_reviews),
           (SELECT COUNT(*) FROM dw.fact_reviews)
) AS x;
GO

/* 8.5 VALIDATION - value-sum reconciliation (must match staging exactly) --- */
SELECT
    (SELECT SUM(TRY_CAST(price AS DECIMAL(12,2)) + TRY_CAST(freight_value AS DECIMAL(12,2)))
       FROM stg.order_items)                                    AS staging_item_total_sum,
    (SELECT SUM(price + freight_value) FROM dw.fact_sales)       AS dw_item_total_sum,
    (SELECT SUM(TRY_CAST(payment_value AS DECIMAL(12,2))) FROM stg.order_payments) AS staging_payment_sum,
    (SELECT SUM(payment_value) FROM dw.fact_payments)             AS dw_payment_sum;
GO

/* 8.6 VALIDATION - orphan / null foreign-key checks (all must be 0) -------- */
SELECT 'fact_sales.customer_key'  AS check_name, COUNT(*) AS null_count FROM dw.fact_sales WHERE customer_key IS NULL
UNION ALL SELECT 'fact_sales.product_key',  COUNT(*) FROM dw.fact_sales WHERE product_key IS NULL
UNION ALL SELECT 'fact_sales.seller_key',   COUNT(*) FROM dw.fact_sales WHERE seller_key IS NULL
UNION ALL SELECT 'fact_sales.date_key',     COUNT(*) FROM dw.fact_sales WHERE date_key IS NULL
UNION ALL SELECT 'fact_payments.customer_key', COUNT(*) FROM dw.fact_payments WHERE customer_key IS NULL
UNION ALL SELECT 'fact_reviews.customer_key',  COUNT(*) FROM dw.fact_reviews WHERE customer_key IS NULL;
GO

/* 8.7 VALIDATION - anomaly checks ------------------------------------------ */
SELECT 'negative delivery lead time' AS check_name, COUNT(*) AS anomaly_count
FROM   dw.fact_sales WHERE delivery_lead_time_days < 0
UNION ALL
SELECT 'duplicate order_id in fact_reviews', COUNT(*) - COUNT(DISTINCT order_id) FROM dw.fact_reviews
UNION ALL
SELECT 'duplicate customer_id in dim_customer', COUNT(*) - COUNT(DISTINCT customer_id) FROM dw.dim_customer;
GO

-- 8.8 Full load log for the report ------------------------------------------
SELECT load_id, step_name, target_table, rows_loaded, status, started_at, finished_at
FROM   etl.load_log
ORDER  BY load_id;
GO

/* 8.9 Final status - only says "complete" when the counts really match ---- */
IF  (SELECT COUNT(*) FROM dw.fact_sales)    = (SELECT COUNT(*) FROM stg.order_items)
AND (SELECT COUNT(*) FROM dw.fact_payments) = (SELECT COUNT(*) FROM stg.order_payments)
AND (SELECT COUNT(*) FROM dw.fact_reviews)  = (SELECT COUNT(DISTINCT order_id) FROM stg.order_reviews)
AND (SELECT COUNT(*) FROM dw.fact_sales) > 0
    PRINT 'Phase 8 complete: facts loaded and validated (all row counts match staging).';
ELSE
    PRINT 'Phase 8 FINISHED WITH PROBLEMS: a fact table is empty or its count does not match staging. Check the PASS/FAIL table and etl.load_log.';
GO
