/* =====================================================================
   PHASE 7b - EXTRACT FROM ADDITIONAL SOURCE TYPES (Task 2)
   Run after: 06_phase7_extract_bulk_insert.sql
   Run before: 07_phase7_transform_load_dimensions.sql

   SOURCE TYPES USED IN THIS PROJECT
     1. CSV        - orders, items, payments, reviews, products, geolocation (script 06)
     2. Relational - OlistOLTP database: dbo.sellers and dbo.customers (this script)
     3. JSON       - product_category_translation.json                (this script)
     4. Excel      - brazil_state_region.xlsx                         (imported with the
                     SSMS Import and Export Wizard - see STEP 3 below)

   HONESTY NOTE FOR THE REPORT: the OlistOLTP tables and the JSON file are
   built from the original Olist CSV files to give the warehouse multiple
   operational source types. Say this in the report. The Excel state-to-region
   table is a small reference file prepared by the team.

   BEFORE RUNNING
     - Copy these into C:\OlistData\ :
         olist_sellers_dataset.csv, olist_customers_dataset.csv  (already there)
         product_category_translation.json                       (new)
     - brazil_state_region.xlsx can stay anywhere; you pick it in the wizard.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   STEP 1 - staging table for the Excel source (created once, never dropped)
   --------------------------------------------------------------------- */
USE OlistDW;
GO
IF OBJECT_ID(N'stg.state_region', N'U') IS NULL
    CREATE TABLE stg.state_region
    (
        state_code  VARCHAR(2)   NULL,
        state_name  NVARCHAR(50) NULL,
        region      VARCHAR(20)  NULL
    );
GO

/* ---------------------------------------------------------------------
   STEP 2a - build the relational source system: database OlistOLTP
   --------------------------------------------------------------------- */
IF DB_ID(N'OlistOLTP') IS NULL
    CREATE DATABASE OlistOLTP;
GO
USE OlistOLTP;
GO
DROP TABLE IF EXISTS dbo.sellers;
DROP TABLE IF EXISTS dbo.customers;
GO
CREATE TABLE dbo.sellers
(
    seller_id               VARCHAR(32)   NOT NULL CONSTRAINT pk_oltp_sellers PRIMARY KEY,
    seller_zip_code_prefix  VARCHAR(10)   NULL,
    seller_city             NVARCHAR(100) NULL,
    seller_state            VARCHAR(2)    NULL
);
CREATE TABLE dbo.customers
(
    customer_id               VARCHAR(32)   NOT NULL CONSTRAINT pk_oltp_customers PRIMARY KEY,
    customer_unique_id        VARCHAR(32)   NULL,
    customer_zip_code_prefix  VARCHAR(10)   NULL,
    customer_city             NVARCHAR(100) NULL,
    customer_state            VARCHAR(2)    NULL
);
GO
BULK INSERT dbo.sellers
FROM 'C:\OlistData\olist_sellers_dataset.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',',
      ROWTERMINATOR='0x0a', CODEPAGE='65001', TABLOCK);
BULK INSERT dbo.customers
FROM 'C:\OlistData\olist_customers_dataset.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',',
      ROWTERMINATOR='0x0a', CODEPAGE='65001', TABLOCK);
GO
SELECT 'OlistOLTP.dbo.sellers' AS source_table, COUNT(*) AS row_count FROM dbo.sellers
UNION ALL
SELECT 'OlistOLTP.dbo.customers', COUNT(*) FROM dbo.customers;
GO

/* ---------------------------------------------------------------------
   STEP 2b - EXTRACT from the relational source into staging.
   The CSV copy loaded by script 06 is used as the baseline: the new
   extract must give exactly the same row count (reconciliation).
   --------------------------------------------------------------------- */
USE OlistDW;
GO
DECLARE @load_id INT, @csv_rows INT, @new_rows INT;

/* sellers */
SELECT @csv_rows = COUNT(*) FROM stg.sellers;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Extract (relational) sellers', 'stg.sellers', 'STARTED');
SET @load_id = SCOPE_IDENTITY();
BEGIN TRY
    TRUNCATE TABLE stg.sellers;
    INSERT INTO stg.sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state)
    SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state
    FROM   OlistOLTP.dbo.sellers;
    SET @new_rows = @@ROWCOUNT;
    UPDATE etl.load_log
    SET rows_read = @new_rows, rows_loaded = @new_rows, rows_rejected = 0,
        finished_at = SYSDATETIME(),
        status = CASE WHEN @new_rows = @csv_rows THEN 'SUCCESS' ELSE 'COUNT MISMATCH vs CSV baseline' END
    WHERE load_id = @load_id;
END TRY
BEGIN CATCH
    UPDATE etl.load_log SET finished_at = SYSDATETIME(), status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
    WHERE load_id = @load_id;
    THROW;
END CATCH;

/* customers */
SELECT @csv_rows = COUNT(*) FROM stg.customers;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Extract (relational) customers', 'stg.customers', 'STARTED');
SET @load_id = SCOPE_IDENTITY();
BEGIN TRY
    TRUNCATE TABLE stg.customers;
    INSERT INTO stg.customers (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state)
    SELECT customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state
    FROM   OlistOLTP.dbo.customers;
    SET @new_rows = @@ROWCOUNT;
    UPDATE etl.load_log
    SET rows_read = @new_rows, rows_loaded = @new_rows, rows_rejected = 0,
        finished_at = SYSDATETIME(),
        status = CASE WHEN @new_rows = @csv_rows THEN 'SUCCESS' ELSE 'COUNT MISMATCH vs CSV baseline' END
    WHERE load_id = @load_id;
END TRY
BEGIN CATCH
    UPDATE etl.load_log SET finished_at = SYSDATETIME(), status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
    WHERE load_id = @load_id;
    THROW;
END CATCH;
GO

/* ---------------------------------------------------------------------
   STEP 2c - EXTRACT the JSON source into stg.category_translation
   (parsed with OPENROWSET(BULK) + OPENJSON)
   --------------------------------------------------------------------- */
DECLARE @load_id INT, @csv_rows INT, @new_rows INT, @json NVARCHAR(MAX);

SELECT @csv_rows = COUNT(*) FROM stg.category_translation;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Extract (JSON) category_translation', 'stg.category_translation', 'STARTED');
SET @load_id = SCOPE_IDENTITY();
BEGIN TRY
    SELECT @json = BulkColumn
    FROM OPENROWSET(BULK 'C:\OlistData\product_category_translation.json', SINGLE_CLOB) AS j;

    TRUNCATE TABLE stg.category_translation;
    INSERT INTO stg.category_translation (product_category_name, product_category_name_english)
    SELECT product_category_name, product_category_name_english
    FROM   OPENJSON(@json)
           WITH (product_category_name         NVARCHAR(100) '$.product_category_name',
                 product_category_name_english NVARCHAR(100) '$.product_category_name_english');
    SET @new_rows = @@ROWCOUNT;
    UPDATE etl.load_log
    SET rows_read = @new_rows, rows_loaded = @new_rows, rows_rejected = 0,
        finished_at = SYSDATETIME(),
        status = CASE WHEN @new_rows = @csv_rows THEN 'SUCCESS' ELSE 'COUNT MISMATCH vs CSV baseline' END
    WHERE load_id = @load_id;
END TRY
BEGIN CATCH
    UPDATE etl.load_log SET finished_at = SYSDATETIME(), status = LEFT('ERROR: ' + ERROR_MESSAGE(), 500)
    WHERE load_id = @load_id;
    THROW;
END CATCH;
GO

/* ---------------------------------------------------------------------
   STEP 3 - EXCEL source (manual, one time)
   In SSMS: right-click database OlistDW -> Tasks -> Import Data...
     Data source      : Microsoft Excel   (file: brazil_state_region.xlsx,
                        version Excel 2007-2016 or later,
                        tick "First row has column names")
     Destination      : SQL Server Native Client / OLE DB Driver for SQL Server,
                        database OlistDW
     Copy data from one or more tables -> sheet 'state_region$'
     Destination table: [stg].[state_region]   (existing table - edit mappings:
                        delete rows in destination table first)
     Run immediately -> Finish. Screenshot each wizard page for the report.
   If the wizard says the 'Microsoft.ACE.OLEDB' provider is not registered,
   install "Microsoft Access Database Engine 2016 Redistributable" (64-bit),
   then reopen SSMS.

   Alternative (T-SQL, needs the same ACE provider plus 'Ad Hoc Distributed
   Queries' enabled by an administrator):
     INSERT INTO stg.state_region (state_code, state_name, region)
     SELECT state_code, state_name, region
     FROM OPENROWSET('Microsoft.ACE.OLEDB.12.0',
          'Excel 12.0;Database=C:\OlistData\brazil_state_region.xlsx;HDR=YES',
          'SELECT * FROM [state_region$]');
   --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------
   STEP 4 - VALIDATION: every source type, with PASS/FAIL
   --------------------------------------------------------------------- */
SELECT source_type, staging_table, expected_rows, actual_rows,
       CASE WHEN expected_rows = actual_rows THEN 'PASS' ELSE 'FAIL' END AS validation_status
FROM (
    SELECT 'Relational' AS source_type, 'stg.sellers' AS staging_table,
           3095 AS expected_rows, (SELECT COUNT(*) FROM stg.sellers) AS actual_rows
    UNION ALL
    SELECT 'Relational', 'stg.customers', 99441, (SELECT COUNT(*) FROM stg.customers)
    UNION ALL
    SELECT 'JSON', 'stg.category_translation', 71, (SELECT COUNT(*) FROM stg.category_translation)
    UNION ALL
    SELECT 'Excel', 'stg.state_region (import it in STEP 3)', 27, (SELECT COUNT(*) FROM stg.state_region)
) AS x;
GO

SELECT load_id, step_name, target_table, rows_loaded, status, started_at, finished_at
FROM   etl.load_log
WHERE  step_name LIKE 'Extract (%'
ORDER  BY load_id;
GO

USE OlistDW;
DROP TABLE IF EXISTS stg.[state_region$];