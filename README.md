# Olist E-commerce Data Warehouse & BI Dashboard

An end-to-end data warehousing and business intelligence solution built using SQL Server, T-SQL, and Power BI to analyze Brazilian e-commerce sales, payments, delivery performance, and customer satisfaction.

## Project Overview

This university project transforms raw e-commerce data into a structured analytical environment for business reporting and decision-making.

I designed a dimensional data warehouse, developed a T-SQL ETL pipeline, created a sales data mart, and built an interactive Power BI dashboard to explore sales trends, business performance, and operational insights.

## Business Problem

Raw transactional data is not always suitable for business analysis. Businesses need a structured and reliable way to combine sales, payment, customer, product, and delivery information to understand performance and identify improvement opportunities.

This project addresses that need by integrating source data into a dimensional warehouse and presenting the results through interactive dashboards.

## Business Questions

* How do sales and revenue change over time?
* Which products, sellers, and locations contribute most to sales?
* What payment methods are most commonly used?
* How does delivery performance vary across orders and locations?
* What patterns appear in customer reviews and satisfaction?
* Which business trends can support better operational decisions?

## Architecture

The solution follows a layered data warehousing architecture.

**Source Systems → ETL Pipeline → Staging Area → Data Warehouse → Data Mart → Power BI**

![Data Warehouse Architecture](docs/architecture.png)

*Click the diagram below to view the full-size architecture image.*

[**View Data Warehouse Architecture**](docs/architecture.png)

## Dimensional Data Model

I designed a star-schema data warehouse with three fact tables and seven dimension tables.

### Fact Tables

* `fact_sales` — sales transactions at order-line grain
* `fact_payments` — payment transaction details
* `fact_reviews` — customer review information

### Dimension Tables

* Date
* Location
* Customer
* Seller
* Product
* Payment Type
* Order Status

The model supports analytical queries across time, geography, products, sellers, payments, and order status.

![Star Schema](docs/star_schema.png)

[**Click here to view the full Star Schema**](docs/star_schema.png)

## ETL Pipeline

I implemented a T-SQL ETL workflow in SQL Server to load and transform source data into the warehouse.

Key implementation features include:

* Loading raw CSV files into staging tables using `BULK INSERT`
* Integrating source data from CSV, Excel, JSON, and relational sources
* Data type conversion and standardization
* De-duplication and data quality checks
* Surrogate-key lookups for dimensional loading
* Derived measures, including delivery delay
* ETL execution logging and audit tracking
* Validation and reconciliation across loading stages

The pipeline is organized into SQL scripts to support repeatable execution and easier maintenance.

## Power BI Dashboard

The Power BI dashboard provides interactive views of sales performance and business operations. It uses measures, filters, and analytical navigation to support detailed exploration.

### 1. Executive Summary

Provides a high-level view of sales performance and key business indicators.

[**Click here to view Executive Summary**](docs/dashboard_page1.png)

[![Executive Summary](docs/dashboard_page1.png)](docs/dashboard_page1.png)

### 2. Trend Analysis

Explores changes in sales performance over time, including trends and year-over-year comparisons.

[**Click here to view Trend Analysis**](docs/dashboard_page2.png)

[![Trend Analysis](docs/dashboard_page2.png)](docs/dashboard_page2.png)

### 3. Interactive Analysis

Supports deeper investigation using interactive filtering, drill-down, roll-up, decomposition, and drill-through features.

[**Click here to view Interactive Analysis**](docs/dashboard_page3.png)

[![Interactive Analysis](docs/dashboard_page3.png)](docs/dashboard_page3.png)

## Key Insights

The dashboard is designed to investigate business patterns such as:

* Sales growth and changes in revenue over time
* Seasonal sales patterns and high-performing periods
* Differences in performance across products and locations
* Payment method distribution
* Delivery performance and delays
* Customer review and satisfaction patterns

**Note:** Add quantified findings only after confirming the figures in your actual dashboard.

## Technologies Used

* **Database:** Microsoft SQL Server
* **Query Language:** T-SQL
* **Database Tools:** SQL Server Management Studio (SSMS)
* **Business Intelligence:** Microsoft Power BI
* **Analytics:** DAX, Power Query
* **Data Warehousing:** Dimensional Modelling, Star Schema
* **ETL:** Staging, Transformation, Validation, Data Loading
* **Analytical Concepts:** Data Mart, OLAP, Drill-Down and Roll-Up

## Repository Structure

```text
olist-data-warehouse-bi/
├── README.md
├── sql/
│   ├── 01_...
│   ├── 02_...
│   └── ...
├── source-files/
│   ├── brazil_state_region.xlsx
│   └── product_category_translation.json
├── powerbi/
│   ├── Olist_DWBI_Theme.json
│   └── Olist_DWBI.pbix
└── docs/
    ├── architecture.png
    ├── star_schema.png
    ├── dashboard_page1.png
    ├── dashboard_page2.png
    └── dashboard_page3.png
```

*The filenames above illustrate the intended structure. Update them to match the files actually present in the repository.*

## How to Run the Project

1. Install Microsoft SQL Server and SQL Server Management Studio.
2. Download the Brazilian E-Commerce Public Dataset by Olist from Kaggle.
3. Place the required CSV files in the configured local data directory, such as `C:\OlistData\`.
4. Create the staging and warehouse databases or schemas using the supplied SQL scripts.
5. Execute the SQL scripts in the documented dependency order.
6. Import any additional Excel or JSON source data required by the pipeline.
7. Run the ETL workflow and validate the loaded data.
8. Open the Power BI report and configure its SQL Server connection to the `OlistDW` database.
9. Refresh the report to explore the dashboard.

**Important:** SQL Server configuration, file paths, database names, and script order may require adjustment for your environment. Follow the actual scripts and project documentation.

## Data Source

The project uses the Brazilian E-Commerce Public Dataset by Olist, available through Kaggle.

The original dataset is not included in this repository. Download it from the official dataset page and review its applicable terms before reuse or redistribution.

## Skills Demonstrated

* SQL Server database development
* T-SQL and ETL pipeline implementation
* Dimensional data modelling
* Data quality validation and reconciliation
* Data mart development
* DAX and Power Query
* Interactive dashboard development
* Business intelligence and analytical reporting

## Future Improvements

* Automate ETL scheduling and monitoring
* Add more advanced customer segmentation
* Extend data quality reporting
* Improve dashboard performance for larger datasets
* Introduce additional analytical measures and drill-through views

## AI Assistance

I used an AI assistant (Claude) to support planning, debugging, and drafting. I reviewed and tested the implementation and validated the results against my project requirements.

---

**Developed as a university project for IT3101 – Data Warehousing and Business Intelligence at SLIIT.**
