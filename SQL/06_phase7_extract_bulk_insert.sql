/* =====================================================================
   PHASE 7 - EXTRACT (CSV -> STAGING) + STAGING VALIDATION
   Run after: 05_phase6_staging_ddl.sql
   Run before: 07_phase7_transform_load_dimensions.sql

   WHAT WAS WRONG: the old version of this file only VALIDATED staging.
   It referred to a Python extract script that was never run, so the
   stg.* tables stayed empty and every later script loaded 0 rows.

   BEFORE RUNNING
     1. Put the 9 CSV files (unzipped) in  C:\OlistData\
     2. The SQL Server service account must be able to read that folder
        (error 4861 "Cannot bulk load ... file could not be opened"
        means a permission or path problem).
     3. Line endings differ per file (checked on the real files):
          order_reviews and category_translation = CRLF  -> 0x0d0a
          the other 7 files                      = LF    -> 0x0a
   ===================================================================== */
USE OlistDW;
GO

/* ---------------------------------------------------------------------
   PART A - EXTRACT: truncate each staging table, BULK INSERT its CSV,
   and write one audit row per file to etl.load_log.
   --------------------------------------------------------------------- */
SET NOCOUNT ON;

DECLARE @path NVARCHAR(260) = N'C:\OlistData\';

DECLARE @files TABLE
(
    id        INT IDENTITY(1,1),
    tbl       SYSNAME,
    file_name NVARCHAR(100),
    row_term  VARCHAR(10)
);

INSERT INTO @files (tbl, file_name, row_term) VALUES
 ('customers',            N'olist_customers_dataset.csv',        '0x0a'),
 ('geolocation',          N'olist_geolocation_dataset.csv',      '0x0a'),
 ('order_items',          N'olist_order_items_dataset.csv',      '0x0a'),
 ('order_payments',       N'olist_order_payments_dataset.csv',   '0x0a'),
 ('order_reviews',        N'olist_order_reviews_dataset.csv',    '0x0d0a'),
 ('orders',               N'olist_orders_dataset.csv',           '0x0a'),
 ('products',             N'olist_products_dataset.csv',         '0x0a'),
 ('sellers',              N'olist_sellers_dataset.csv',          '0x0a'),
 ('category_translation', N'product_category_name_translation.csv', '0x0d0a');

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @files);
DECLARE @tbl SYSNAME, @file NVARCHAR(100), @rt VARCHAR(10);
DECLARE @sql NVARCHAR(MAX), @load_id INT, @cnt INT;

WHILE @i <= @n
BEGIN
    SELECT @tbl = tbl, @file = file_name, @rt = row_term FROM @files WHERE id = @i;

    INSERT INTO etl.load_log (step_name, target_table, status)
    VALUES ('Extract ' + @tbl, 'stg.' + @tbl, 'STARTED');
    SET @load_id = SCOPE_IDENTITY();

    BEGIN TRY
        SET @sql = N'TRUNCATE TABLE stg.' + QUOTENAME(@tbl) + N';';
        EXEC (@sql);

        SET @sql = N'BULK INSERT stg.' + QUOTENAME(@tbl)
                 + N' FROM ''' + @path + @file + N''''
                 + N' WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'','
                 + N' FIELDTERMINATOR = '','', ROWTERMINATOR = ''' + @rt + N''','
                 + N' CODEPAGE = ''65001'', TABLOCK);';
        EXEC (@sql);

        SET @sql = N'SELECT @c = COUNT(*) FROM stg.' + QUOTENAME(@tbl) + N';';
        EXEC sp_executesql @sql, N'@c INT OUTPUT', @c = @cnt OUTPUT;

        UPDATE etl.load_log
        SET    rows_read = @cnt, rows_loaded = @cnt, rows_rejected = 0,
               finished_at = SYSDATETIME(), status = 'SUCCESS'
        WHERE  load_id = @load_id;
    END TRY
    BEGIN CATCH
        UPDATE etl.load_log
        SET    finished_at = SYSDATETIME(),
               status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
        WHERE  load_id = @load_id;
    END CATCH;

    SET @i += 1;
END;
GO

/* ---------------------------------------------------------------------
   PART B - STAGING VALIDATION (original checks, unchanged)
   --------------------------------------------------------------------- */

/* 1. Confirm all expected source row counts */
WITH actual_counts AS
(
    SELECT 'customers' AS table_name, COUNT_BIG(*) AS actual_rows FROM stg.customers
    UNION ALL SELECT 'geolocation',          COUNT_BIG(*) FROM stg.geolocation
    UNION ALL SELECT 'order_items',          COUNT_BIG(*) FROM stg.order_items
    UNION ALL SELECT 'order_payments',       COUNT_BIG(*) FROM stg.order_payments
    UNION ALL SELECT 'order_reviews',        COUNT_BIG(*) FROM stg.order_reviews
    UNION ALL SELECT 'orders',               COUNT_BIG(*) FROM stg.orders
    UNION ALL SELECT 'products',             COUNT_BIG(*) FROM stg.products
    UNION ALL SELECT 'sellers',              COUNT_BIG(*) FROM stg.sellers
    UNION ALL SELECT 'category_translation', COUNT_BIG(*) FROM stg.category_translation
),
expected_counts AS
(
    SELECT *
    FROM (VALUES
        ('customers',             CAST(99441   AS BIGINT)),
        ('geolocation',           CAST(1000163 AS BIGINT)),
        ('order_items',           CAST(112650  AS BIGINT)),
        ('order_payments',        CAST(103886  AS BIGINT)),
        ('order_reviews',         CAST(99224   AS BIGINT)),
        ('orders',                CAST(99441   AS BIGINT)),
        ('products',              CAST(32951   AS BIGINT)),
        ('sellers',               CAST(3095    AS BIGINT)),
        ('category_translation',  CAST(71      AS BIGINT))
    ) AS x(table_name, expected_rows)
)
SELECT e.table_name, e.expected_rows, a.actual_rows,
       CASE WHEN a.actual_rows = e.expected_rows THEN 'PASS' ELSE 'FAIL' END AS validation_status
FROM   expected_counts AS e
LEFT JOIN actual_counts AS a ON a.table_name = e.table_name
ORDER  BY e.table_name;
GO

/* 2. Confirm ETL audit entries (any ERROR text explains a FAIL above) */
SELECT load_id, step_name, target_table, rows_read, rows_loaded, rows_rejected,
       status, started_at, finished_at,
       DATEDIFF(SECOND, started_at, finished_at) AS seconds_taken
FROM   etl.load_log
WHERE  step_name LIKE 'Extract %'
ORDER  BY load_id;
GO

/* 3. Important source-key length checks */
SELECT MAX(LEN(customer_id)) AS max_customer_id,
       MAX(LEN(customer_unique_id)) AS max_customer_unique_id
FROM   stg.customers;
GO

SELECT MAX(LEN(order_id)) AS max_order_id,
       MAX(LEN(product_id)) AS max_product_id,
       MAX(LEN(seller_id)) AS max_seller_id
FROM   stg.order_items;
GO

/* 4. Basic malformed/null key checks (all must be 0) */
SELECT 'customers.customer_id' AS check_name, COUNT(*) AS bad_rows
FROM stg.customers WHERE customer_id IS NULL OR LEN(customer_id) <> 32
UNION ALL
SELECT 'orders.order_id', COUNT(*)
FROM stg.orders WHERE order_id IS NULL OR LEN(order_id) <> 32
UNION ALL
SELECT 'order_items.order_id', COUNT(*)
FROM stg.order_items WHERE order_id IS NULL OR LEN(order_id) <> 32
UNION ALL
SELECT 'products.product_id', COUNT(*)
FROM stg.products WHERE product_id IS NULL OR LEN(product_id) <> 32
UNION ALL
SELECT 'sellers.seller_id', COUNT(*)
FROM stg.sellers WHERE seller_id IS NULL OR LEN(seller_id) <> 32;
GO
