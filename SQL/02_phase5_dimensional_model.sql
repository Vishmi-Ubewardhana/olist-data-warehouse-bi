/* =====================================================================
   PHASE 5 - DIMENSIONAL MODEL (STAR SCHEMA) - DDL
   Platform : Microsoft SQL Server (T-SQL)
   Design   : 3 fact tables + 7 dimension tables, surrogate integer keys
   Run after: 01_phase4_architecture.sql
   Safe to re-run: drops facts first, then dimensions.
   ===================================================================== */
USE OlistDW;
GO

/* ---------- 0. Drop in dependency order (facts before dimensions) ---------- */
DROP TABLE IF EXISTS dw.fact_reviews;
DROP TABLE IF EXISTS dw.fact_payments;
DROP TABLE IF EXISTS dw.fact_sales;
DROP TABLE IF EXISTS dw.dim_order_status;
DROP TABLE IF EXISTS dw.dim_payment_type;
DROP TABLE IF EXISTS dw.dim_product;
DROP TABLE IF EXISTS dw.dim_seller;
DROP TABLE IF EXISTS dw.dim_customer;
DROP TABLE IF EXISTS dw.dim_location;
DROP TABLE IF EXISTS dw.dim_date;
GO

/* =====================================================================
   1. DIMENSION TABLES
   ===================================================================== */

/* 1.1 DimDate - conformed, shared by all fact tables.
       Hierarchy: Year > Quarter > Month > Day                          */
CREATE TABLE dw.dim_date
(
    date_key      INT          NOT NULL CONSTRAINT pk_dim_date PRIMARY KEY,  -- YYYYMMDD
    full_date     DATE         NOT NULL CONSTRAINT uq_dim_date_full UNIQUE,
    day_of_month  TINYINT      NOT NULL,
    day_name      VARCHAR(10)  NOT NULL,
    month_number  TINYINT      NOT NULL,
    month_name    VARCHAR(10)  NOT NULL,
    quarter_number TINYINT     NOT NULL CONSTRAINT ck_dim_date_q CHECK (quarter_number BETWEEN 1 AND 4),
    year_number   SMALLINT     NOT NULL,
    week_of_year  TINYINT      NOT NULL,
    is_weekend    BIT          NOT NULL
);
GO

/* 1.2 DimLocation - conformed, shared by DimCustomer and DimSeller.
       Hierarchy: Region > State > City > Zip prefix                    */
CREATE TABLE dw.dim_location
(
    location_key     INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_location PRIMARY KEY,
    zip_code_prefix  INT           NOT NULL CONSTRAINT uq_dim_location_zip UNIQUE,
    city             NVARCHAR(100) NULL,
    state_code       CHAR(2)       NULL,
    region           VARCHAR(20)   NOT NULL
        CONSTRAINT ck_dim_location_region CHECK
        (region IN ('North','Northeast','Central-West','Southeast','South','Unknown')),
    latitude         DECIMAL(9,6)  NULL,
    longitude        DECIMAL(9,6)  NULL
);
GO

/* 1.3 DimCustomer  (natural keys kept for traceability)                */
CREATE TABLE dw.dim_customer
(
    customer_key              INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_customer PRIMARY KEY,
    customer_id               VARCHAR(32)   NOT NULL CONSTRAINT uq_dim_customer_id UNIQUE, -- order-level id
    customer_unique_id        VARCHAR(32)   NOT NULL,                                        -- real person
    customer_city             NVARCHAR(100) NULL,
    customer_state            CHAR(2)       NULL,
    customer_zip_code_prefix  INT           NULL,
    location_key              INT           NULL
        CONSTRAINT fk_dim_customer_location REFERENCES dw.dim_location (location_key)
);
GO

/* 1.4 DimSeller                                                        */
CREATE TABLE dw.dim_seller
(
    seller_key              INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_seller PRIMARY KEY,
    seller_id               VARCHAR(32)   NOT NULL CONSTRAINT uq_dim_seller_id UNIQUE,
    seller_city             NVARCHAR(100) NULL,
    seller_state            CHAR(2)       NULL,
    seller_zip_code_prefix  INT           NULL,
    location_key            INT           NULL
        CONSTRAINT fk_dim_seller_location REFERENCES dw.dim_location (location_key)
);
GO

/* 1.5 DimProduct.  Hierarchy: Category > Product                       */
CREATE TABLE dw.dim_product
(
    product_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_product PRIMARY KEY,
    product_id         VARCHAR(32)   NOT NULL CONSTRAINT uq_dim_product_id UNIQUE,
    category_name_pt   NVARCHAR(100) NOT NULL,
    category_name_en   NVARCHAR(100) NOT NULL,
    product_weight_g   DECIMAL(10,2) NULL,
    product_length_cm  DECIMAL(8,2)  NULL,
    product_height_cm  DECIMAL(8,2)  NULL,
    product_width_cm   DECIMAL(8,2)  NULL,
    product_photos_qty INT           NULL
);
GO

/* 1.6 DimPaymentType                                                   */
CREATE TABLE dw.dim_payment_type
(
    payment_type_key INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_payment_type PRIMARY KEY,
    payment_type     VARCHAR(20) NOT NULL CONSTRAINT uq_dim_payment_type UNIQUE
);
GO

/* 1.7 DimOrderStatus                                                   */
CREATE TABLE dw.dim_order_status
(
    order_status_key INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_order_status PRIMARY KEY,
    order_status     VARCHAR(20) NOT NULL CONSTRAINT uq_dim_order_status UNIQUE
);
GO

/* =====================================================================
   2. FACT TABLES
   ===================================================================== */

/* 2.1 FactSales
       Business process : an item sold within an order
       Grain            : one row per order line (order_id + order_item_id)
       Additive measures: price, freight_value, item_total
       Semi-additive/derived: delivery_delay_days, delivery_lead_time_days  */
CREATE TABLE dw.fact_sales
(
    sales_key               BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_fact_sales PRIMARY KEY,
    -- degenerate dimensions
    order_id                VARCHAR(32)  NOT NULL,
    order_item_id           SMALLINT     NOT NULL,
    -- foreign keys (role-playing date: purchase / delivered / estimated)
    date_key                INT NOT NULL CONSTRAINT fk_fs_date       REFERENCES dw.dim_date (date_key),
    delivered_date_key      INT NULL     CONSTRAINT fk_fs_deliv_date REFERENCES dw.dim_date (date_key),
    estimated_date_key      INT NULL     CONSTRAINT fk_fs_est_date   REFERENCES dw.dim_date (date_key),
    customer_key            INT NOT NULL CONSTRAINT fk_fs_customer   REFERENCES dw.dim_customer (customer_key),
    product_key             INT NOT NULL CONSTRAINT fk_fs_product    REFERENCES dw.dim_product (product_key),
    seller_key              INT NOT NULL CONSTRAINT fk_fs_seller     REFERENCES dw.dim_seller (seller_key),
    order_status_key        INT NOT NULL CONSTRAINT fk_fs_status     REFERENCES dw.dim_order_status (order_status_key),
    -- measures
    price                   DECIMAL(10,2) NOT NULL,
    freight_value           DECIMAL(10,2) NOT NULL,
    item_total              AS (price + freight_value) PERSISTED,
    delivery_delay_days     DECIMAL(9,2) NULL,   -- actual delivery minus estimated (negative = early)
    delivery_lead_time_days DECIMAL(9,2) NULL,   -- purchase to delivery
    -- the grain is enforced by a unique constraint
    CONSTRAINT uq_fact_sales_grain UNIQUE (order_id, order_item_id)
);
GO

/* 2.2 FactPayments
       Grain: one row per payment line of an order (order_id + payment_sequential) */
CREATE TABLE dw.fact_payments
(
    payment_key          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_fact_payments PRIMARY KEY,
    order_id             VARCHAR(32) NOT NULL,
    payment_sequential   SMALLINT    NOT NULL,
    date_key             INT NOT NULL CONSTRAINT fk_fp_date          REFERENCES dw.dim_date (date_key),
    customer_key         INT NOT NULL CONSTRAINT fk_fp_customer      REFERENCES dw.dim_customer (customer_key),
    payment_type_key     INT NOT NULL CONSTRAINT fk_fp_payment_type  REFERENCES dw.dim_payment_type (payment_type_key),
    payment_value        DECIMAL(10,2) NOT NULL,
    payment_installments SMALLINT NOT NULL,
    CONSTRAINT uq_fact_payments_grain UNIQUE (order_id, payment_sequential)
);
GO

/* 2.3 FactReviews
       Grain: one row per reviewed order (after removing duplicate reviews) */
CREATE TABLE dw.fact_reviews
(
    review_key                   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_fact_reviews PRIMARY KEY,
    order_id                     VARCHAR(32) NOT NULL CONSTRAINT uq_fact_reviews_order UNIQUE,
    review_id                    VARCHAR(32) NULL,
    date_key                     INT NOT NULL CONSTRAINT fk_fr_date     REFERENCES dw.dim_date (date_key),
    customer_key                 INT NOT NULL CONSTRAINT fk_fr_customer REFERENCES dw.dim_customer (customer_key),
    review_score                 TINYINT NOT NULL CONSTRAINT ck_fr_score CHECK (review_score BETWEEN 1 AND 5),
    has_comment                  BIT NOT NULL,
    review_answer_lead_time_days DECIMAL(9,2) NULL
);
GO

/* =====================================================================
   3. INDEXES on foreign-key columns (speeds up star joins)
   ===================================================================== */
CREATE INDEX ix_fs_date       ON dw.fact_sales (date_key);
CREATE INDEX ix_fs_customer   ON dw.fact_sales (customer_key);
CREATE INDEX ix_fs_product    ON dw.fact_sales (product_key);
CREATE INDEX ix_fs_seller     ON dw.fact_sales (seller_key);
CREATE INDEX ix_fs_status     ON dw.fact_sales (order_status_key);
CREATE INDEX ix_fp_date       ON dw.fact_payments (date_key);
CREATE INDEX ix_fp_customer   ON dw.fact_payments (customer_key);
CREATE INDEX ix_fp_type       ON dw.fact_payments (payment_type_key);
CREATE INDEX ix_fr_date       ON dw.fact_reviews (date_key);
CREATE INDEX ix_fr_customer   ON dw.fact_reviews (customer_key);
CREATE INDEX ix_cust_location ON dw.dim_customer (location_key);
CREATE INDEX ix_sell_location ON dw.dim_seller (location_key);
GO

PRINT 'Phase 5: star schema created (7 dimensions, 3 facts).';
GO
