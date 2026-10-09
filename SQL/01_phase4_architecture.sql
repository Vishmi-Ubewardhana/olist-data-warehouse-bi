/* =====================================================================
   PHASE 4 - DATA WAREHOUSE ARCHITECTURE (implemented as database objects)
   Platform : Microsoft SQL Server (T-SQL), run in SSMS
   Project  : Olist E-Commerce Data Warehouse
   Purpose  : Create the database and one schema per architecture layer:
                stg  = Staging area           (raw copy of source files)
                dw   = Enterprise Data Warehouse (star schema)
                mart = Data Mart              (department-specific views)
                etl  = ETL control / audit    (load logging)
   ===================================================================== */

-- 1. Create the database ------------------------------------------------
USE master;
GO
IF DB_ID(N'OlistDW') IS NULL
    CREATE DATABASE OlistDW;
GO
USE OlistDW;
GO

-- 2. Create one schema per layer ---------------------------------------
IF SCHEMA_ID(N'stg')  IS NULL EXEC (N'CREATE SCHEMA stg  AUTHORIZATION dbo');
IF SCHEMA_ID(N'dw')   IS NULL EXEC (N'CREATE SCHEMA dw   AUTHORIZATION dbo');
IF SCHEMA_ID(N'mart') IS NULL EXEC (N'CREATE SCHEMA mart AUTHORIZATION dbo');
IF SCHEMA_ID(N'etl')  IS NULL EXEC (N'CREATE SCHEMA etl  AUTHORIZATION dbo');
GO

-- 3. ETL audit table: every load step writes one row here ---------------
IF OBJECT_ID(N'etl.load_log', N'U') IS NOT NULL DROP TABLE etl.load_log;
GO
CREATE TABLE etl.load_log
(
    load_id        INT IDENTITY(1,1) CONSTRAINT pk_load_log PRIMARY KEY,
    step_name      VARCHAR(100)  NOT NULL,      -- e.g. 'Load dw.dim_customer'
    target_table   VARCHAR(100)  NOT NULL,
    rows_read      INT           NULL,
    rows_loaded    INT           NULL,
    rows_rejected  INT           NULL,
    started_at     DATETIME2(0)  NOT NULL CONSTRAINT df_load_log_start DEFAULT SYSDATETIME(),
    finished_at    DATETIME2(0)  NULL,
    status         VARCHAR(500)  NOT NULL CONSTRAINT df_load_log_status DEFAULT 'STARTED'
);
GO

-- 4. Architecture catalogue: documents the layers inside the database ----
IF OBJECT_ID(N'etl.layer_catalog', N'U') IS NOT NULL DROP TABLE etl.layer_catalog;
GO
CREATE TABLE etl.layer_catalog
(
    layer_order   TINYINT       NOT NULL CONSTRAINT pk_layer_catalog PRIMARY KEY,
    layer_name    VARCHAR(40)   NOT NULL,
    schema_name   VARCHAR(10)   NULL,
    purpose       VARCHAR(300)  NOT NULL,
    contents      VARCHAR(300)  NOT NULL
);
GO
INSERT INTO etl.layer_catalog (layer_order, layer_name, schema_name, purpose, contents) VALUES
(1, 'Data Source Layer',       NULL,   'Operational (OLTP) extracts of the Olist marketplace',
    '9 CSV files: orders, order_items, order_payments, order_reviews, customers, products, sellers, geolocation, category_translation'),
(2, 'Data Integration Layer',  'etl',  'Extract, transform and load; audit of every load step',
    'T-SQL load scripts (INSERT...SELECT), etl.load_log'),
(3, 'Staging Area',            'stg',  'Untouched copy of the source files; decouples file reading from transformation',
    'stg.customers, stg.orders, stg.order_items, ... (one table per file)'),
(4, 'Enterprise Data Warehouse','dw',  'Integrated, historical, query-optimised star schema with conformed dimensions',
    '7 dimension tables (dim_*) and 3 fact tables (fact_*)'),
(5, 'Data Mart',               'mart', 'Department-specific subset for Sales and Category managers, built only from dw objects',
    'mart.v_sales_performance (view, created in Phase 9)'),
(6, 'Presentation Layer',      NULL,   'OLAP-style analytical queries and Power BI dashboards',
    'Executive Summary, Trend Analysis and Interactive Analysis pages');
GO

-- 5. Evidence query (take a screenshot of this result) -------------------
SELECT layer_order, layer_name, schema_name, purpose, contents
FROM   etl.layer_catalog
ORDER  BY layer_order;

SELECT s.name AS schema_name
FROM   sys.schemas AS s
WHERE  s.name IN (N'stg', N'dw', N'mart', N'etl')
ORDER  BY s.name;
GO
