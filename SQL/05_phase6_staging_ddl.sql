/* =====================================================================
   PHASE 6 - STAGING AREA - DDL
   Platform : Microsoft SQL Server (T-SQL)
   Purpose  : One staging table per source CSV, sized from the actual
              files (max observed length + headroom), typed loosely
              (mostly VARCHAR) because staging must accept the source
              as-is, even if a value would not fit the final DW type.
   Notes    : - All 9 files are UTF-8, comma-delimited, LF line endings
                (confirmed: 0 CRLF line endings found in any file).
              - order_reviews contains quoted fields with embedded
                commas, newlines and accented Portuguese characters -
                handled in Phase 6 script 06 with FORMAT='CSV' and
                FIELDQUOTE='"' (requires SQL Server 2017+).
              - product_category_name_translation.csv has a UTF-8 BOM
                before the header row only; FIRSTROW=2 in script 06
                skips the header, so the BOM never reaches the data.
   Run after: 04_phase5_verify_model.sql
   ===================================================================== */
USE OlistDW;
GO

DROP TABLE IF EXISTS stg.order_items;
DROP TABLE IF EXISTS stg.order_payments;
DROP TABLE IF EXISTS stg.order_reviews;
DROP TABLE IF EXISTS stg.orders;
DROP TABLE IF EXISTS stg.customers;
DROP TABLE IF EXISTS stg.products;
DROP TABLE IF EXISTS stg.sellers;
DROP TABLE IF EXISTS stg.geolocation;
DROP TABLE IF EXISTS stg.category_translation;
GO

-- 99,441 rows, max lengths: id 32, zip 5, city 32, state 2
CREATE TABLE stg.customers
(
    customer_id               VARCHAR(32)   NULL,
    customer_unique_id        VARCHAR(32)   NULL,
    customer_zip_code_prefix  VARCHAR(10)   NULL,   -- kept as text in staging; cast to INT on load
    customer_city             NVARCHAR(100) NULL,
    customer_state            VARCHAR(2)    NULL
);
GO

-- 1,000,163 rows, max lengths: zip 5, lat 23, lng 19, city 38, state 2
CREATE TABLE stg.geolocation
(
    geolocation_zip_code_prefix VARCHAR(10)   NULL,
    geolocation_lat              VARCHAR(30)   NULL,
    geolocation_lng              VARCHAR(30)   NULL,
    geolocation_city             NVARCHAR(100) NULL,
    geolocation_state            VARCHAR(2)    NULL
);
GO

-- 112,650 rows
CREATE TABLE stg.order_items
(
    order_id             VARCHAR(32)   NULL,
    order_item_id        VARCHAR(5)    NULL,
    product_id           VARCHAR(32)   NULL,
    seller_id            VARCHAR(32)   NULL,
    shipping_limit_date  VARCHAR(25)   NULL,
    price                VARCHAR(15)   NULL,
    freight_value        VARCHAR(15)   NULL
);
GO

-- 103,886 rows
CREATE TABLE stg.order_payments
(
    order_id              VARCHAR(32) NULL,
    payment_sequential    VARCHAR(5)  NULL,
    payment_type          VARCHAR(20) NULL,
    payment_installments  VARCHAR(5)  NULL,
    payment_value         VARCHAR(15) NULL
);
GO

-- 99,224 rows. review_comment_message max observed length 208, headroom to 1000.
-- Contains embedded newlines/commas inside quoted fields - see script 06.
CREATE TABLE stg.order_reviews
(
    review_id                VARCHAR(32)    NULL,
    order_id                 VARCHAR(32)    NULL,
    review_score             VARCHAR(2)     NULL,
    review_comment_title     NVARCHAR(100)  NULL,
    review_comment_message   NVARCHAR(1000) NULL,
    review_creation_date     VARCHAR(25)    NULL,
    review_answer_timestamp  VARCHAR(25)    NULL
);
GO

-- 99,441 rows
CREATE TABLE stg.orders
(
    order_id                       VARCHAR(32) NULL,
    customer_id                    VARCHAR(32) NULL,
    order_status                   VARCHAR(20) NULL,
    order_purchase_timestamp       VARCHAR(25) NULL,
    order_approved_at              VARCHAR(25) NULL,
    order_delivered_carrier_date   VARCHAR(25) NULL,
    order_delivered_customer_date  VARCHAR(25) NULL,
    order_estimated_delivery_date  VARCHAR(25) NULL
);
GO

-- 32,951 rows
CREATE TABLE stg.products
(
    product_id                  VARCHAR(32)   NULL,
    product_category_name       NVARCHAR(100) NULL,
    product_name_lenght         VARCHAR(5)    NULL,
    product_description_lenght  VARCHAR(6)    NULL,
    product_photos_qty          VARCHAR(5)    NULL,
    product_weight_g            VARCHAR(10)   NULL,
    product_length_cm           VARCHAR(6)    NULL,
    product_height_cm           VARCHAR(6)    NULL,
    product_width_cm            VARCHAR(6)    NULL
);
GO

-- 3,095 rows
CREATE TABLE stg.sellers
(
    seller_id               VARCHAR(32)   NULL,
    seller_zip_code_prefix  VARCHAR(10)   NULL,
    seller_city             NVARCHAR(100) NULL,
    seller_state             VARCHAR(2)    NULL
);
GO

-- 71 rows
CREATE TABLE stg.category_translation
(
    product_category_name          NVARCHAR(100) NULL,
    product_category_name_english  NVARCHAR(100) NULL
);
GO

PRINT 'Phase 6: 9 staging tables created in schema stg.';
GO
