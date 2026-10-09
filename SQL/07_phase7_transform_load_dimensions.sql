/* =====================================================================
   PHASE 7 - ETL: TRANSFORM + LOAD DIMENSIONS
   Reads stg.* tables, applies every cleansing rule from Phase 1/3
   profiling, and loads the 7 conformed dimensions in dw.
   Order matters: dim_location before dim_customer/dim_seller
   (foreign key); dim_date is independent (already loaded in script 03).

   RE-RUNNABLE BY DESIGN: this script can be run again at any time -
   even after Phase 8 has already loaded the fact tables - because
   Step 0 below clears the fact tables FIRST (children before parents).
   Without Step 0, re-running this script fails with errors like
   "Cannot truncate table ... referenced by a FOREIGN KEY constraint"
   and then "Violation of UNIQUE/PRIMARY KEY constraint", because the
   dimension DELETE/TRUNCATE statements further down are blocked by
   fact rows that already point at them, so the old rows never get
   cleared before the new ones are inserted.
   ===================================================================== */
USE OlistDW;
GO

/* =====================================================================
   STEP 0 - RESET: clear fact tables (children) before dimensions
   (parents). Safe to run even if the fact tables are already empty.
   ===================================================================== */
DECLARE @load_id INT, @rows INT;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Reset before dimension reload', 'dw.fact_sales/fact_payments/fact_reviews', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

DELETE FROM dw.fact_reviews;
DELETE FROM dw.fact_payments;
DELETE FROM dw.fact_sales;
DBCC CHECKIDENT ('dw.fact_reviews', RESEED, 0);
DBCC CHECKIDENT ('dw.fact_payments', RESEED, 0);
DBCC CHECKIDENT ('dw.fact_sales', RESEED, 0);

UPDATE etl.load_log SET finished_at = SYSDATETIME(), status = 'SUCCESS' WHERE load_id = @load_id;
GO

/* =====================================================================
   7.1  DIM_LOCATION
   Rule: aggregate geolocation to one row per zip prefix
         (mean lat/lng; most frequent city/state = mode).
         Add zip prefixes that appear in customers/sellers but not
         in geolocation, with lat/lng left NULL.
         Derive region from state.
   ===================================================================== */
DECLARE @load_id INT, @rows INT;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Transform+Load dim_location', 'dw.dim_location', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

DELETE FROM dw.dim_customer;   -- children must be emptied first (FK to dim_location); facts are already empty (Step 0)
DELETE FROM dw.dim_seller;     -- TRUNCATE is not allowed here either - a FOREIGN KEY references this table
DELETE FROM dw.dim_location;
DBCC CHECKIDENT ('dw.dim_customer', RESEED, 0);
DBCC CHECKIDENT ('dw.dim_seller', RESEED, 0);
DBCC CHECKIDENT ('dw.dim_location', RESEED, 0);

;WITH geo_clean AS (
    SELECT  TRY_CAST(geolocation_zip_code_prefix AS INT) AS zip,
            TRY_CAST(geolocation_lat AS DECIMAL(9,6))    AS lat,
            TRY_CAST(geolocation_lng AS DECIMAL(9,6))    AS lng,
            LTRIM(RTRIM(geolocation_city))                AS city,
            UPPER(LTRIM(RTRIM(geolocation_state)))        AS state
    FROM    stg.geolocation
    WHERE   TRY_CAST(geolocation_zip_code_prefix AS INT) IS NOT NULL
),
geo_latlng AS (   -- average position per zip
    SELECT zip, AVG(lat) AS lat, AVG(lng) AS lng
    FROM   geo_clean
    GROUP  BY zip
),
geo_mode AS (     -- most frequent (city, state) per zip = "mode"
    SELECT zip, city, state,
           ROW_NUMBER() OVER (PARTITION BY zip ORDER BY COUNT(*) DESC, city) AS rn
    FROM   geo_clean
    GROUP  BY zip, city, state
),
geo_agg AS (
    SELECT ll.zip, m.city, m.state, ll.lat, ll.lng
    FROM   geo_latlng ll
    JOIN   geo_mode m ON m.zip = ll.zip AND m.rn = 1
),
extra_zips AS (    -- zips known from customers/sellers but absent from geolocation
    SELECT DISTINCT
           TRY_CAST(customer_zip_code_prefix AS INT) AS zip,
           LTRIM(RTRIM(customer_city))                AS city,
           UPPER(LTRIM(RTRIM(customer_state)))        AS state
    FROM   stg.customers
    WHERE  TRY_CAST(customer_zip_code_prefix AS INT) IS NOT NULL
    UNION
    SELECT DISTINCT
           TRY_CAST(seller_zip_code_prefix AS INT),
           LTRIM(RTRIM(seller_city)),
           UPPER(LTRIM(RTRIM(seller_state)))
    FROM   stg.sellers
    WHERE  TRY_CAST(seller_zip_code_prefix AS INT) IS NOT NULL
),
all_zips AS (
    SELECT zip, city, state, lat, lng FROM geo_agg
    UNION ALL
    SELECT e.zip, e.city, e.state, NULL, NULL
    FROM   extra_zips e
    WHERE  NOT EXISTS (SELECT 1 FROM geo_agg g WHERE g.zip = e.zip)
)
INSERT INTO dw.dim_location (zip_code_prefix, city, state_code, region, latitude, longitude)
SELECT  zip, city, state,
        CASE
            WHEN state IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'North'
            WHEN state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
            WHEN state IN ('DF','GO','MT','MS') THEN 'Central-West'
            WHEN state IN ('ES','MG','RJ','SP') THEN 'Southeast'
            WHEN state IN ('PR','RS','SC') THEN 'South'
            ELSE 'Unknown'
        END AS region,
        lat, lng
FROM    all_zips;

SET @rows = @@ROWCOUNT;
UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
WHERE load_id = @load_id;
GO

/* =====================================================================
   7.2  DIM_CUSTOMER
   Rule: one row per customer_id; look up location_key by zip prefix.
   ===================================================================== */
DECLARE @load_id INT, @rows INT;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Transform+Load dim_customer', 'dw.dim_customer', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

INSERT INTO dw.dim_customer
    (customer_id, customer_unique_id, customer_city, customer_state,
     customer_zip_code_prefix, location_key)
SELECT  c.customer_id,
        c.customer_unique_id,
        LTRIM(RTRIM(c.customer_city)),
        UPPER(LTRIM(RTRIM(c.customer_state))),
        TRY_CAST(c.customer_zip_code_prefix AS INT),
        l.location_key
FROM    stg.customers c
LEFT JOIN dw.dim_location l ON l.zip_code_prefix = TRY_CAST(c.customer_zip_code_prefix AS INT);

SET @rows = @@ROWCOUNT;
UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
WHERE load_id = @load_id;
GO

/* =====================================================================
   7.3  DIM_SELLER
   ===================================================================== */
DECLARE @load_id INT, @rows INT;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Transform+Load dim_seller', 'dw.dim_seller', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

INSERT INTO dw.dim_seller
    (seller_id, seller_city, seller_state, seller_zip_code_prefix, location_key)
SELECT  s.seller_id,
        LTRIM(RTRIM(s.seller_city)),
        UPPER(LTRIM(RTRIM(s.seller_state))),
        TRY_CAST(s.seller_zip_code_prefix AS INT),
        l.location_key
FROM    stg.sellers s
LEFT JOIN dw.dim_location l ON l.zip_code_prefix = TRY_CAST(s.seller_zip_code_prefix AS INT);

SET @rows = @@ROWCOUNT;
UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
WHERE load_id = @load_id;
GO

/* =====================================================================
   7.4  DIM_PRODUCT
   Rule: missing category -> 'unknown'; English name falls back to the
         Portuguese name when no translation row matches.
   ===================================================================== */
DECLARE @load_id INT, @rows INT;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Transform+Load dim_product', 'dw.dim_product', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

DELETE FROM dw.dim_product;
DBCC CHECKIDENT ('dw.dim_product', RESEED, 0);

INSERT INTO dw.dim_product
    (product_id, category_name_pt, category_name_en, product_weight_g,
     product_length_cm, product_height_cm, product_width_cm, product_photos_qty)
SELECT  p.product_id,
        cat_pt,
        COALESCE(t.product_category_name_english, cat_pt) AS category_name_en,
        TRY_CAST(p.product_weight_g AS DECIMAL(10,2)),
        TRY_CAST(p.product_length_cm AS DECIMAL(8,2)),
        TRY_CAST(p.product_height_cm AS DECIMAL(8,2)),
        TRY_CAST(p.product_width_cm AS DECIMAL(8,2)),
        TRY_CAST(p.product_photos_qty AS INT)
FROM    stg.products p
CROSS APPLY (SELECT COALESCE(NULLIF(LTRIM(RTRIM(p.product_category_name)), ''), 'unknown') AS cat_pt) x
LEFT JOIN stg.category_translation t
       ON t.product_category_name = x.cat_pt;

SET @rows = @@ROWCOUNT;
UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS'
WHERE load_id = @load_id;
GO

/* =====================================================================
   7.5  DIM_PAYMENT_TYPE  and  7.6  DIM_ORDER_STATUS
   Rule: distinct values from the source.
   ===================================================================== */
DECLARE @load_id INT, @rows INT;
INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Transform+Load dim_payment_type', 'dw.dim_payment_type', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

DELETE FROM dw.dim_payment_type; DBCC CHECKIDENT ('dw.dim_payment_type', RESEED, 0);
INSERT INTO dw.dim_payment_type (payment_type)
SELECT DISTINCT LTRIM(RTRIM(payment_type)) FROM stg.order_payments WHERE payment_type IS NOT NULL;
SET @rows = @@ROWCOUNT;
UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS' WHERE load_id = @load_id;

INSERT INTO etl.load_log (step_name, target_table, status)
VALUES ('Transform+Load dim_order_status', 'dw.dim_order_status', 'STARTED');
SET @load_id = SCOPE_IDENTITY();

DELETE FROM dw.dim_order_status; DBCC CHECKIDENT ('dw.dim_order_status', RESEED, 0);
INSERT INTO dw.dim_order_status (order_status)
SELECT DISTINCT LTRIM(RTRIM(order_status)) FROM stg.orders WHERE order_status IS NOT NULL;
SET @rows = @@ROWCOUNT;
UPDATE etl.load_log SET rows_loaded = @rows, finished_at = SYSDATETIME(), status = 'SUCCESS' WHERE load_id = @load_id;
GO

-- Evidence -----------------------------------------------------------------
SELECT 'dim_location' t, COUNT(*) rows_now FROM dw.dim_location
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'dim_seller', COUNT(*) FROM dw.dim_seller
UNION ALL SELECT 'dim_product', COUNT(*) FROM dw.dim_product
UNION ALL SELECT 'dim_payment_type', COUNT(*) FROM dw.dim_payment_type
UNION ALL SELECT 'dim_order_status', COUNT(*) FROM dw.dim_order_status;

SELECT step_name, target_table, rows_loaded, status, started_at, finished_at
FROM   etl.load_log WHERE step_name LIKE 'Transform+Load dim%' ORDER BY load_id;
GO
