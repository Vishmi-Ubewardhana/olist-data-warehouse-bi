/* =====================================================================
   PHASE 5 (continued) - Populate DimDate
   DimDate does not come from the source files; it is generated.
   Range 2016-01-01 to 2018-12-31 covers the dataset (Sep-2016 to Oct-2018).
   Expected result: 1,096 rows.
   ===================================================================== */
USE OlistDW;
GO

DELETE FROM dw.dim_date;   -- (TRUNCATE is not allowed once foreign keys reference this table)
GO

WITH calendar AS
(
    SELECT CAST('2016-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM calendar WHERE d < '2018-12-31'
)
INSERT INTO dw.dim_date
       (date_key, full_date, day_of_month, day_name, month_number, month_name,
        quarter_number, year_number, week_of_year, is_weekend)
SELECT  CONVERT(INT, CONVERT(CHAR(8), d, 112))          AS date_key,
        d                                                AS full_date,
        DAY(d)                                           AS day_of_month,
        DATENAME(WEEKDAY, d)                             AS day_name,
        MONTH(d)                                         AS month_number,
        DATENAME(MONTH, d)                               AS month_name,
        DATEPART(QUARTER, d)                             AS quarter_number,
        YEAR(d)                                          AS year_number,
        DATEPART(ISO_WEEK, d)                            AS week_of_year,
        CASE WHEN DATEDIFF(DAY, '19000101', d) % 7 IN (5, 6) THEN 1 ELSE 0 END AS is_weekend
FROM    calendar
OPTION (MAXRECURSION 0);
GO

SELECT COUNT(*) AS dim_date_rows, MIN(full_date) AS first_day, MAX(full_date) AS last_day
FROM   dw.dim_date;
GO
