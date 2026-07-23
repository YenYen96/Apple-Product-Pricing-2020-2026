--Kiểm tra 
SELECT COUNT(*) AS Date_Count
FROM dbo.dim_date;

SELECT COUNT(*) AS Product_Count
FROM dbo.dim_product;

SELECT COUNT(*) AS Platform_Count
FROM dbo.dim_platform;

SELECT COUNT(*) AS Condition_Count
FROM dbo.dim_condition;

SELECT COUNT(*) AS Sale_Event_Count
FROM dbo.dim_sale_event;

SELECT COUNT(*) AS Stock_Status_Count
FROM dbo.dim_stock_status;

SELECT *
from apple_products_pricing_2020_2026

--Vòng đời sản phẩm
--1/Tạo View

USE [Apple_Price];
GO

DROP VIEW IF EXISTS dbo.vw_product_lifecycle;
GO

CREATE VIEW dbo.vw_product_lifecycle
AS

WITH lifecycle_base AS
(
    SELECT
        TRY_CONVERT(DATE, a.[Date]) AS Snapshot_Date,

        p.Product_Key,
        p.Product_Category,
        p.Model_Name,

        LTRIM(RTRIM(a.Platform)) AS Platform_Name,

        LTRIM(RTRIM(a.[Condition])) AS Condition_Name,

        COALESCE(
            NULLIF(LTRIM(RTRIM(a.Sale_Event)), ''),
            'No Event'
        ) AS Sale_Event_Name,

        LTRIM(RTRIM(a.Stock_Status)) AS Stock_Status_Name,

        p.First_Seen_Date,

        DATEDIFF(
            MONTH,
            p.First_Seen_Date,
            TRY_CONVERT(DATE, a.[Date])
        ) AS Product_Age_Month,

        TRY_CONVERT(
            DECIMAL(10,4),
            a.Discount_Pct
        ) AS Discount_Pct

    FROM dbo.apple_products_pricing_2020_2026 a

    INNER JOIN dbo.dim_product p
        ON p.Product_Category =
            LTRIM(RTRIM(a.Product_Category))

       AND p.Model_Name =
            LTRIM(RTRIM(a.Model_Name))

    WHERE TRY_CONVERT(DATE, a.[Date]) IS NOT NULL
),

daily_snapshot AS(
    SELECT
        Snapshot_Date,
        Product_Key,
        Product_Category,
        Model_Name,
        Platform_Name,
        Condition_Name,
        Sale_Event_Name,
        Stock_Status_Name,
        First_Seen_Date,
        Product_Age_Month,
        AVG(Discount_Pct) AS Daily_Discount_Pct,
        COUNT(*) AS Source_Row_Count
    FROM lifecycle_base
    WHERE Product_Age_Month >= 0
      AND Discount_Pct IS NOT NULL
    GROUP BY
        Snapshot_Date,
        Product_Key,
        Product_Category,
        Model_Name,
        Platform_Name,
        Condition_Name,
        Sale_Event_Name,
        Stock_Status_Name,
        First_Seen_Date,
        Product_Age_Month
)
SELECT
    Snapshot_Date,
    Product_Key,
    Product_Category,
    Model_Name,
    Platform_Name,
    Condition_Name,
    Sale_Event_Name,
    Stock_Status_Name,
    First_Seen_Date,
    Product_Age_Month,
    CASE
        WHEN Product_Age_Month BETWEEN 0 AND 6
            THEN '01. 0-6 Months'
        WHEN Product_Age_Month BETWEEN 7 AND 12
            THEN '02. 7-12 Months'
        WHEN Product_Age_Month BETWEEN 13 AND 24
            THEN '03. 13-24 Months'
        WHEN Product_Age_Month BETWEEN 25 AND 36
            THEN '04. 25-36 Months'
        ELSE '05. 37+ Months'
    END AS Product_Age_Bucket,
    Daily_Discount_Pct,
    Source_Row_Count
FROM daily_snapshot;
GO
--2/Check
SELECT *
FROM dbo.vw_product_lifecycle
ORDER BY
    Product_Category,
    Model_Name,
    Product_Age_Month;

=========================
SELECT *
FROM apple_products_pricing_2020_2026
=========================
--1/ Kiểm tra dataset
SELECT 
    Count(*) AS Total_Rows,
    Min(date) AS Begin_Date,
    Max(date) AS End_Date, 
    Count(Distinct Product_Category) AS Total_Category,
    Count(Distinct Model_Name) AS Total_Models,
    Count (Distinct Platform) AS Total_Platforms
FROM apple_products_pricing_2020_2026

--2/ Tìm 10 model có discount trung bình cao nhất. Chỉ lấy những model có ít nhất 100 thống kê
WITH model_stats AS (
    SELECT 
        Product_Category,
        Model_Name,
        CAST(AVG(Discount_Pct) AS decimal (10,2)) AS Avg_Discount_Pct
    FROM apple_products_pricing_2020_2026
    WHERE Discount_Pct IS NOT NULL
    GROUP BY Product_Category, Model_Name
),
ranked_models AS (
    SELECT *,
        DENSE_RANK() OVER (ORDER BY Avg_Discount_Pct DESC) AS Discount_Rank
    FROM model_stats
)
SELECT 
    CONCAT(Product_Category, ' - ', Model_Name) AS Model_Label,
    *
FROM ranked_models
WHERE Discount_Rank <= 10
ORDER BY Discount_Rank, Model_Name

--3/Sale-event nào có discount cao nhất và tỷ lệ stock-out rate lớn nhất
SELECT 
    Product_Category,
    Sale_Event,
    CAST(AVG(Discount_Pct) AS decimal (10,2)) AS Avg_Discount_Pct,
    cast(100.0* SUM(CASE
                WHEN Stock_Status = 'Out of Stock' THEN 1 ELSE 0 END)/ NULLIF(COUNT(*),0) 
    as decimal(10,2)
        ) AS Out_Of_Stock_Rate_Pct
FROM apple_products_pricing_2020_2026
GROUP BY Product_Category,Sale_Event
ORDER BY Product_Category, 
        Avg_Discount_Pct DESC, 
        Out_Of_Stock_Rate_Pct DESC

--4/Amazon và Flipkart khác nhau thế nào theo category và condition
SELECT 
    Product_Category,
    Condition,
    CAST(AVG(CASE WHEN Platform = 'Amazon' THEN Current_Price_USD END) AS decimal (10,2)) AS Amazon_Avg_Price,
    CAST(AVG(CASE WHEN Platform = 'Flipkart' THEN Current_Price_USD END) AS decimal (10,2)) AS Flipkart_Avg_Price,
    CAST(AVG(CASE WHEN Platform = 'Amazon' THEN Discount_Pct END) AS decimal (10,2)) AS Amazon_Avg_Discount_Pct,
    CAST(AVG(CASE WHEN Platform = 'Flipkart' THEN Discount_Pct END) AS decimal (10,2)) AS Flipkart_Avg_Discount_Pct,
    COUNT(CASE WHEN Platform = 'Amazon' THEN 1 END) AS Amazon_Count,
    COUNT(CASE WHEN Platform = 'Flipkart' THEN 1 END) AS Flipkart_count
FROM apple_products_pricing_2020_2026
GROUP BY Product_Category,Condition
ORDER BY Product_Category,Condition

--5/Discount và current price thay đổi theo tháng như thế nào.Tính MoM
WITH monthly_price AS (
    SELECT
        Product_Category,
        DATEFROMPARTS(YEAR([Date]),MONTH([Date]),1) AS Month_Start,
        CAST(AVG(Current_Price_USD) AS decimal(10,2)) AS Avg_Current_Price_USD,
        CAST(AVG(Discount_Pct)  AS decimal(10,2)) AS Avg_Discount_Pct
    FROM apple_products_pricing_2020_2026
    GROUP BY Product_Category,
        DATEFROMPARTS(YEAR([Date]),MONTH([Date]),1) 
),
monthly_comparison AS(
    SELECT *,
        LAG(Avg_Current_Price_USD) OVER (PARTITION BY Product_Category ORDER BY Month_Start)  AS Previous_Month_Price,
        LAG(Avg_Discount_Pct) OVER(PARTITION BY Product_Category ORDER BY Month_Start) AS Previous_Month_Discount
    FROM monthly_price
)
SELECT
    Product_Category,
    Month_Start,
    Avg_Current_Price_USD,
    Avg_Discount_Pct,
    CAST( 100.0 *(Avg_Current_Price_USD - Previous_Month_Price )/ NULLIF(Previous_Month_Price, 0) AS DECIMAL(10,2)) AS Price_MoM_Pct,
    CAST( Avg_Discount_Pct - Previous_Month_Discount AS DECIMAL(10,2)) AS Discount_MoM_Change_pp
FROM monthly_comparison
ORDER BY
    Product_Category,
    Month_Start;

--6/ Mỗi model mất bao lâu để lần đầu đạt được discount 20%
WITH daily_model_discount AS (
    SELECT 
        date,
        Product_Category,
        Model_Name,
        CAST(AVG(Discount_Pct) AS decimal(10,2)) AS Daily_Avg_Discount_Pct
    from apple_products_pricing_2020_2026
    GROUP BY date,
        Product_Category,
        Model_Name
),
model_markdown AS (
    SELECT 
        Product_Category,
        Model_Name,
        Min (date) as First_Seen_Date,
        Min (case when Daily_Avg_Discount_Pct >=20 THEN date END) AS Frist_20Pct_Discount_Date
    FROM daily_model_discount
    GROUP BY Product_Category, Model_Name
)
SELECT 
    Product_Category,
    Model_Name,
    First_Seen_Date,
    Frist_20Pct_Discount_Date,
    DATEDIFF(DAY,First_Seen_Date,Frist_20Pct_Discount_Date) AS Day_To_20Pct_Discount,
    DATEDIFF(MONTH,First_Seen_Date,Frist_20Pct_Discount_Date) AS Month_To_20Pct_Discount,
    CASE WHEN Frist_20Pct_Discount_Date IS NULL THEN 'Never reached 20% Disccount' ELSE 'Reached 20%' END AS Markdown_Status
FROM model_markdown
ORDER BY Month_To_20Pct_Discount,Product_Category, Model_Name

--7/ Sale Event tạo thêm bao nhiêu discount sau khi kiểm soát model, platform, condition và thời gian (tháng)?
WITH pricing_base AS(
    SELECT Product_Category, Model_Name, Platform, Condition, Sale_Event,Discount_Pct,
            DATEFROMPARTS(YEAR([Date]),MONTH([Date]),1) AS Month_Start
    FROM apple_products_pricing_2020_2026
    WHERE Discount_Pct IS not null
),
none_event_baseline AS (
    SELECT Product_Category, Model_Name, Platform, Condition, Sale_Event,Month_Start,
            AVG(Discount_Pct) as Non_Event_Discount_Pct
    from pricing_base
    WHERE Sale_Event ='None'
    GROUP by Product_Category, Model_Name, Platform, Condition, Sale_Event,Month_Start
),
event_pricing AS(
    SELECT Product_Category, Model_Name, Platform, Condition, Sale_Event,Month_Start,
            AVG(Discount_Pct) as Event_Discount_Pct
    FROM pricing_base
    WHERE Sale_Event <> 'None'
    GROUP by Product_Category, Model_Name, Platform, Condition, Sale_Event,Month_Start
),
matched_event AS(
    SELECT e.Product_Category,
        e.Model_Name,
        e.Sale_Event,
        e.Event_Discount_Pct,
        b.Non_Event_Discount_Pct,
        e.Event_Discount_Pct - b.Non_Event_Discount_Pct AS Event_Lift_pp
    FROM event_pricing e
    JOIN none_event_baseline b ON b.Product_Category = e.Product_Category
    AND b.Model_Name = e.Model_Name
    AND b.Platform = e.Platform
    AND b.Condition = e.Condition
    AND b.Month_Start = e.Month_Start
)
SELECT Product_Category, Sale_Event,
    COUNT(*) AS Matched_Comparison_Count,
    COUNT(DISTINCT Model_Name) as Matchched_Model_Count,
    CAST(AVG(Event_Discount_Pct) AS decimal (10,2)) AS Event_Avg_Discount_Pct,
    CAST(AVG(Non_Event_Discount_Pct) AS decimal (10,2)) AS Baseline_Avg_Discount_Pct,
    CAST(AVG(Event_Lift_pp) AS decimal (10,2)) AS Controlled_Event_lift_pp
FROM matched_event
GROUP BY Product_Category, Sale_Event
ORDER BY Controlled_Event_lift_pp DESC


-- SELECT
--     AVG(Controlled_Event_Lift_pp)
-- FROM a





