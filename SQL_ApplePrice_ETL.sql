/*==============================================================
  APPLE PRICING DIMENSION MODEL
  Database: Apple_Price
  Source: dbo.apple_products_pricing_2020_2026
==============================================================*/

USE [Apple_Price];
GO


/*==============================================================
  0. KIỂM TRA BẢNG NGUỒN
==============================================================*/

IF OBJECT_ID(N'dbo.apple_products_pricing_2020_2026', N'U') IS NULL
BEGIN
    RAISERROR(
        N'Không tìm thấy bảng dbo.apple_products_pricing_2020_2026 trong database Apple_Price.',
        16,
        1
    );

    RETURN;
END;
GO


/*==============================================================
  1. TẠO CÁC BẢNG DIMENSION NẾU CHƯA CÓ
==============================================================*/

---------------------------------------------------------------
-- 1.1 DIM_DATE
---------------------------------------------------------------

IF OBJECT_ID(N'dbo.dim_date', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_date
    (
        Date_Key DATE NOT NULL
            CONSTRAINT PK_dim_date PRIMARY KEY,

        [Year] INT NOT NULL,
        Quarter_Number INT NOT NULL,
        Quarter_Name VARCHAR(2) NOT NULL,

        Month_Number INT NOT NULL,
        Month_Name VARCHAR(20) NOT NULL,

        Year_Month CHAR(7) NOT NULL,
        Year_Month_Number INT NOT NULL,

        Day_Number INT NOT NULL,
        Day_Name VARCHAR(20) NOT NULL,
        Day_Of_Week_Number INT NOT NULL,

        Week_Number INT NOT NULL,
        Is_Weekend BIT NOT NULL,

        Created_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_dim_date_created_at
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


---------------------------------------------------------------
-- 1.2 DIM_PRODUCT
---------------------------------------------------------------

IF OBJECT_ID(N'dbo.dim_product', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_product
    (
        Product_Key INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dim_product PRIMARY KEY,

        Product_Category VARCHAR(100) NOT NULL,
        Model_Name VARCHAR(200) NOT NULL,

        First_Seen_Date DATE NULL,
        Last_Seen_Date DATE NULL,

        Created_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_dim_product_created_at
            DEFAULT SYSUTCDATETIME(),

        Updated_At DATETIME2(0) NULL,

        CONSTRAINT UQ_dim_product
            UNIQUE (Product_Category, Model_Name)
    );
END;
GO


---------------------------------------------------------------
-- 1.3 DIM_PLATFORM
---------------------------------------------------------------

IF OBJECT_ID(N'dbo.dim_platform', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_platform
    (
        Platform_Key INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dim_platform PRIMARY KEY,

        Platform_Name VARCHAR(100) NOT NULL,

        Created_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_dim_platform_created_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT UQ_dim_platform
            UNIQUE (Platform_Name)
    );
END;
GO


---------------------------------------------------------------
-- 1.4 DIM_CONDITION
---------------------------------------------------------------

IF OBJECT_ID(N'dbo.dim_condition', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_condition
    (
        Condition_Key INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dim_condition PRIMARY KEY,

        Condition_Name VARCHAR(100) NOT NULL,

        Created_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_dim_condition_created_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT UQ_dim_condition
            UNIQUE (Condition_Name)
    );
END;
GO


---------------------------------------------------------------
-- 1.5 DIM_SALE_EVENT
---------------------------------------------------------------

IF OBJECT_ID(N'dbo.dim_sale_event', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_sale_event
    (
        Sale_Event_Key INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dim_sale_event PRIMARY KEY,

        Sale_Event_Name VARCHAR(100) NOT NULL,

        Created_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_dim_sale_event_created_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT UQ_dim_sale_event
            UNIQUE (Sale_Event_Name)
    );
END;
GO


---------------------------------------------------------------
-- 1.6 DIM_STOCK_STATUS
---------------------------------------------------------------

IF OBJECT_ID(N'dbo.dim_stock_status', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_stock_status
    (
        Stock_Status_Key INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dim_stock_status PRIMARY KEY,

        Stock_Status_Name VARCHAR(100) NOT NULL,

        Created_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_dim_stock_status_created_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT UQ_dim_stock_status
            UNIQUE (Stock_Status_Name)
    );
END;
GO


/*==============================================================
  2. XÓA CÁC PROCEDURE CŨ NẾU ĐÃ TỒN TẠI
==============================================================*/

IF OBJECT_ID(N'dbo.sp_refresh_all_dimensions', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_all_dimensions;

IF OBJECT_ID(N'dbo.sp_refresh_dim_date', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_dim_date;

IF OBJECT_ID(N'dbo.sp_refresh_dim_product', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_dim_product;

IF OBJECT_ID(N'dbo.sp_refresh_dim_platform', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_dim_platform;

IF OBJECT_ID(N'dbo.sp_refresh_dim_condition', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_dim_condition;

IF OBJECT_ID(N'dbo.sp_refresh_dim_sale_event', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_dim_sale_event;

IF OBJECT_ID(N'dbo.sp_refresh_dim_stock_status', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_refresh_dim_stock_status;
GO


/*==============================================================
  3. TẠO PROCEDURE REFRESH DIM_DATE
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_dim_date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartDate DATE;
    DECLARE @MaxSourceDate DATE;
    DECLARE @EndDate DATE;

    SELECT
        @StartDate =
            MIN(TRY_CONVERT(DATE, [Date])),

        @MaxSourceDate =
            MAX(TRY_CONVERT(DATE, [Date]))

    FROM dbo.apple_products_pricing_2020_2026

    WHERE TRY_CONVERT(DATE, [Date]) IS NOT NULL;


    IF @StartDate IS NULL OR @MaxSourceDate IS NULL
    BEGIN
        RAISERROR(
            N'Không tìm thấy giá trị Date hợp lệ trong bảng nguồn.',
            16,
            1
        );

        RETURN;
    END;


    -- Tạo lịch đến cuối năm của ngày lớn nhất
    SET @EndDate =
        DATEFROMPARTS(
            YEAR(@MaxSourceDate),
            12,
            31
        );


    ;WITH DateSeries AS
    (
        SELECT
            @StartDate AS Date_Key

        UNION ALL

        SELECT
            DATEADD(DAY, 1, Date_Key)

        FROM DateSeries

        WHERE Date_Key < @EndDate
    )

    INSERT INTO dbo.dim_date
    (
        Date_Key,
        [Year],
        Quarter_Number,
        Quarter_Name,
        Month_Number,
        Month_Name,
        Year_Month,
        Year_Month_Number,
        Day_Number,
        Day_Name,
        Day_Of_Week_Number,
        Week_Number,
        Is_Weekend
    )

    SELECT
        ds.Date_Key,

        YEAR(ds.Date_Key)
            AS [Year],

        DATEPART(QUARTER, ds.Date_Key)
            AS Quarter_Number,

        CONCAT(
            'Q',
            DATEPART(QUARTER, ds.Date_Key)
        ) AS Quarter_Name,

        MONTH(ds.Date_Key)
            AS Month_Number,

        DATENAME(MONTH, ds.Date_Key)
            AS Month_Name,

        CONVERT(CHAR(7), ds.Date_Key, 126)
            AS Year_Month,

        YEAR(ds.Date_Key) * 100
            + MONTH(ds.Date_Key)
            AS Year_Month_Number,

        DAY(ds.Date_Key)
            AS Day_Number,

        DATENAME(WEEKDAY, ds.Date_Key)
            AS Day_Name,

        -- Monday = 1, Sunday = 7
        (
            (
                DATEDIFF(
                    DAY,
                    CONVERT(DATE, '19000101', 112),
                    ds.Date_Key
                ) % 7
            ) + 7
        ) % 7 + 1
            AS Day_Of_Week_Number,

        DATEPART(ISO_WEEK, ds.Date_Key)
            AS Week_Number,

        CASE
            WHEN
                (
                    (
                        DATEDIFF(
                            DAY,
                            CONVERT(DATE, '19000101', 112),
                            ds.Date_Key
                        ) % 7
                    ) + 7
                ) % 7 + 1 IN (6, 7)
            THEN 1
            ELSE 0
        END AS Is_Weekend

    FROM DateSeries ds

    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.dim_date d
        WHERE d.Date_Key = ds.Date_Key
    )

    OPTION (MAXRECURSION 0);
END;
GO


/*==============================================================
  4. TẠO PROCEDURE REFRESH DIM_PRODUCT
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_dim_product
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF OBJECT_ID(N'tempdb..#src_product', N'U') IS NOT NULL
        DROP TABLE #src_product;


    SELECT
        LTRIM(RTRIM(Product_Category))
            AS Product_Category,

        LTRIM(RTRIM(Model_Name))
            AS Model_Name,

        MIN(TRY_CONVERT(DATE, [Date]))
            AS First_Seen_Date,

        MAX(TRY_CONVERT(DATE, [Date]))
            AS Last_Seen_Date

    INTO #src_product

    FROM dbo.apple_products_pricing_2020_2026

    WHERE Product_Category IS NOT NULL
      AND Model_Name IS NOT NULL
      AND LTRIM(RTRIM(Product_Category)) <> ''
      AND LTRIM(RTRIM(Model_Name)) <> ''
      AND TRY_CONVERT(DATE, [Date]) IS NOT NULL

    GROUP BY
        LTRIM(RTRIM(Product_Category)),
        LTRIM(RTRIM(Model_Name));


    -----------------------------------------------------------
    -- Cập nhật First/Last Seen cho sản phẩm đã tồn tại
    -----------------------------------------------------------

    UPDATE d

    SET
        d.First_Seen_Date =
            CASE
                WHEN d.First_Seen_Date IS NULL
                    THEN s.First_Seen_Date

                WHEN s.First_Seen_Date < d.First_Seen_Date
                    THEN s.First_Seen_Date

                ELSE d.First_Seen_Date
            END,

        d.Last_Seen_Date =
            CASE
                WHEN d.Last_Seen_Date IS NULL
                    THEN s.Last_Seen_Date

                WHEN s.Last_Seen_Date > d.Last_Seen_Date
                    THEN s.Last_Seen_Date

                ELSE d.Last_Seen_Date
            END,

        d.Updated_At =
            SYSUTCDATETIME()

    FROM dbo.dim_product d

    INNER JOIN #src_product s
        ON d.Product_Category = s.Product_Category
       AND d.Model_Name = s.Model_Name

    WHERE d.First_Seen_Date IS NULL
       OR d.Last_Seen_Date IS NULL
       OR s.First_Seen_Date < d.First_Seen_Date
       OR s.Last_Seen_Date > d.Last_Seen_Date;


    -----------------------------------------------------------
    -- Thêm sản phẩm mới
    -----------------------------------------------------------

    INSERT INTO dbo.dim_product
    (
        Product_Category,
        Model_Name,
        First_Seen_Date,
        Last_Seen_Date
    )

    SELECT
        s.Product_Category,
        s.Model_Name,
        s.First_Seen_Date,
        s.Last_Seen_Date

    FROM #src_product s

    WHERE NOT EXISTS
    (
        SELECT 1

        FROM dbo.dim_product d

        WHERE d.Product_Category = s.Product_Category
          AND d.Model_Name = s.Model_Name
    );


    DROP TABLE #src_product;
END;
GO


/*==============================================================
  5. TẠO PROCEDURE REFRESH DIM_PLATFORM
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_dim_platform
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ;WITH SourcePlatform AS
    (
        SELECT DISTINCT
            LTRIM(RTRIM(Platform))
                AS Platform_Name

        FROM dbo.apple_products_pricing_2020_2026

        WHERE Platform IS NOT NULL
          AND LTRIM(RTRIM(Platform)) <> ''
    )

    INSERT INTO dbo.dim_platform
    (
        Platform_Name
    )

    SELECT
        s.Platform_Name

    FROM SourcePlatform s

    WHERE NOT EXISTS
    (
        SELECT 1

        FROM dbo.dim_platform d

        WHERE d.Platform_Name = s.Platform_Name
    );
END;
GO


/*==============================================================
  6. TẠO PROCEDURE REFRESH DIM_CONDITION
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_dim_condition
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ;WITH SourceCondition AS
    (
        SELECT DISTINCT
            LTRIM(RTRIM([Condition]))
                AS Condition_Name

        FROM dbo.apple_products_pricing_2020_2026

        WHERE [Condition] IS NOT NULL
          AND LTRIM(RTRIM([Condition])) <> ''
    )

    INSERT INTO dbo.dim_condition
    (
        Condition_Name
    )

    SELECT
        s.Condition_Name

    FROM SourceCondition s

    WHERE NOT EXISTS
    (
        SELECT 1

        FROM dbo.dim_condition d

        WHERE d.Condition_Name = s.Condition_Name
    );
END;
GO


/*==============================================================
  7. TẠO PROCEDURE REFRESH DIM_SALE_EVENT
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_dim_sale_event
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ;WITH SourceSaleEvent AS
    (
        SELECT DISTINCT
            COALESCE(
                NULLIF(
                    LTRIM(RTRIM(Sale_Event)),
                    ''
                ),
                'No Event'
            ) AS Sale_Event_Name

        FROM dbo.apple_products_pricing_2020_2026
    )

    INSERT INTO dbo.dim_sale_event
    (
        Sale_Event_Name
    )

    SELECT
        s.Sale_Event_Name

    FROM SourceSaleEvent s

    WHERE NOT EXISTS
    (
        SELECT 1

        FROM dbo.dim_sale_event d

        WHERE d.Sale_Event_Name = s.Sale_Event_Name
    );
END;
GO


/*==============================================================
  8. TẠO PROCEDURE REFRESH DIM_STOCK_STATUS
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_dim_stock_status
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ;WITH SourceStockStatus AS
    (
        SELECT DISTINCT
            LTRIM(RTRIM(Stock_Status))
                AS Stock_Status_Name

        FROM dbo.apple_products_pricing_2020_2026

        WHERE Stock_Status IS NOT NULL
          AND LTRIM(RTRIM(Stock_Status)) <> ''
    )

    INSERT INTO dbo.dim_stock_status
    (
        Stock_Status_Name
    )

    SELECT
        s.Stock_Status_Name

    FROM SourceStockStatus s

    WHERE NOT EXISTS
    (
        SELECT 1

        FROM dbo.dim_stock_status d

        WHERE d.Stock_Status_Name = s.Stock_Status_Name
    );
END;
GO


/*==============================================================
  9. TẠO PROCEDURE TỔNG
==============================================================*/

CREATE PROCEDURE dbo.sp_refresh_all_dimensions
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC dbo.sp_refresh_dim_date;
        EXEC dbo.sp_refresh_dim_product;
        EXEC dbo.sp_refresh_dim_platform;
        EXEC dbo.sp_refresh_dim_condition;
        EXEC dbo.sp_refresh_dim_sale_event;
        EXEC dbo.sp_refresh_dim_stock_status;

        COMMIT TRANSACTION;

        PRINT 'All dimension tables refreshed successfully.';
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT 'Dimension refresh failed.';
        PRINT ERROR_MESSAGE();

        THROW;
    END CATCH;
END;
GO


/*==============================================================
  10. KIỂM TRA CÁC PROCEDURE ĐÃ ĐƯỢC TẠO
==============================================================*/

SELECT
    DB_NAME() AS Database_Name,
    SCHEMA_NAME(schema_id) AS Schema_Name,
    name AS Procedure_Name

FROM sys.procedures

WHERE name LIKE 'sp_refresh_dim%'
   OR name = 'sp_refresh_all_dimensions'

ORDER BY name;
GO


/*==============================================================
  11. CHẠY REFRESH TẤT CẢ DIMENSION
==============================================================*/

EXEC dbo.sp_refresh_all_dimensions;
GO


/*==============================================================
  12. KIỂM TRA KẾT QUẢ
==============================================================*/

SELECT
    'dim_date' AS Table_Name,
    COUNT(*) AS Row_Count
FROM dbo.dim_date

UNION ALL

SELECT
    'dim_product',
    COUNT(*)
FROM dbo.dim_product

UNION ALL

SELECT
    'dim_platform',
    COUNT(*)
FROM dbo.dim_platform

UNION ALL

SELECT
    'dim_condition',
    COUNT(*)
FROM dbo.dim_condition

UNION ALL

SELECT
    'dim_sale_event',
    COUNT(*)
FROM dbo.dim_sale_event

UNION ALL

SELECT
    'dim_stock_status',
    COUNT(*)
FROM dbo.dim_stock_status;
GO


/*Khi nào có dữ liệu mới, chạy:*/

USE [Apple_Price];
GO

EXEC dbo.sp_refresh_all_dimensions;
GO

/*Tạo bảng fact bằng join*/
USE [Apple_Price];
GO

IF OBJECT_ID(N'dbo.fact_price_snapshot', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_price_snapshot
    (
        Price_Snapshot_Key BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_fact_price_snapshot PRIMARY KEY,

        Date_Key DATE NOT NULL,
        Product_Key INT NOT NULL,
        Platform_Key INT NOT NULL,
        Condition_Key INT NOT NULL,
        Sale_Event_Key INT NOT NULL,
        Stock_Status_Key INT NOT NULL,

        Product_Age_Month INT NULL,

        Launch_Price_USD DECIMAL(18,2) NULL,
        Launch_Price_INR DECIMAL(18,2) NULL,
        Current_Price_USD DECIMAL(18,2) NULL,
        Current_Price_INR DECIMAL(18,2) NULL,

        Discount_Pct DECIMAL(10,2) NULL,
        Rating DECIMAL(4,2) NULL,
        Reviews_Count BIGINT NULL,

        Loaded_At DATETIME2(0) NOT NULL
            CONSTRAINT DF_fact_loaded_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_fact_date
            FOREIGN KEY (Date_Key)
            REFERENCES dbo.dim_date(Date_Key),

        CONSTRAINT FK_fact_product
            FOREIGN KEY (Product_Key)
            REFERENCES dbo.dim_product(Product_Key),

        CONSTRAINT FK_fact_platform
            FOREIGN KEY (Platform_Key)
            REFERENCES dbo.dim_platform(Platform_Key),

        CONSTRAINT FK_fact_condition
            FOREIGN KEY (Condition_Key)
            REFERENCES dbo.dim_condition(Condition_Key),

        CONSTRAINT FK_fact_sale_event
            FOREIGN KEY (Sale_Event_Key)
            REFERENCES dbo.dim_sale_event(Sale_Event_Key),

        CONSTRAINT FK_fact_stock_status
            FOREIGN KEY (Stock_Status_Key)
            REFERENCES dbo.dim_stock_status(Stock_Status_Key)
    );
END;
GO

TRUNCATE TABLE dbo.fact_price_snapshot;

INSERT INTO dbo.fact_price_snapshot
(
    Date_Key,
    Product_Key,
    Platform_Key,
    Condition_Key,
    Sale_Event_Key,
    Stock_Status_Key,

    Product_Age_Month,

    Launch_Price_USD,
    Launch_Price_INR,
    Current_Price_USD,
    Current_Price_INR,

    Discount_Pct,
    Rating,
    Reviews_Count
)
SELECT
    TRY_CONVERT(DATE, a.[Date]) AS Date_Key,

    p.Product_Key,
    pf.Platform_Key,
    c.Condition_Key,
    se.Sale_Event_Key,
    ss.Stock_Status_Key,

    DATEDIFF(
        MONTH,
        p.First_Seen_Date,
        TRY_CONVERT(DATE, a.[Date])
    ) AS Product_Age_Month,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Launch_Price_USD
    ) AS Launch_Price_USD,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Launch_Price_INR
    ) AS Launch_Price_INR,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Current_Price_USD
    ) AS Current_Price_USD,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Current_Price_INR
    ) AS Current_Price_INR,

    TRY_CONVERT(
        DECIMAL(10,2),
        a.Discount_Pct
    ) AS Discount_Pct,

    TRY_CONVERT(
        DECIMAL(4,2),
        a.Rating
    ) AS Rating,

    TRY_CONVERT(
        BIGINT,
        a.Reviews_Count
    ) AS Reviews_Count

FROM dbo.apple_products_pricing_2020_2026 a

INNER JOIN dbo.dim_product p
    ON p.Product_Category =
        LTRIM(RTRIM(a.Product_Category))
   AND p.Model_Name =
        LTRIM(RTRIM(a.Model_Name))

INNER JOIN dbo.dim_platform pf
    ON pf.Platform_Name =
        LTRIM(RTRIM(a.Platform))

INNER JOIN dbo.dim_condition c
    ON c.Condition_Name =
        LTRIM(RTRIM(a.[Condition]))

INNER JOIN dbo.dim_sale_event se
    ON se.Sale_Event_Name =
        COALESCE(
            NULLIF(LTRIM(RTRIM(a.Sale_Event)), ''),
            'None'
        )

INNER JOIN dbo.dim_stock_status ss
    ON ss.Stock_Status_Name =
        LTRIM(RTRIM(a.Stock_Status))

WHERE TRY_CONVERT(DATE, a.[Date]) IS NOT NULL;
GO

--NẠp dữ liệu-
TRUNCATE TABLE dbo.fact_price_snapshot;

INSERT INTO dbo.fact_price_snapshot
(
    Date_Key,
    Product_Key,
    Platform_Key,
    Condition_Key,
    Sale_Event_Key,
    Stock_Status_Key,

    Product_Age_Month,

    Launch_Price_USD,
    Launch_Price_INR,
    Current_Price_USD,
    Current_Price_INR,

    Discount_Pct,
    Rating,
    Reviews_Count
)
SELECT
    TRY_CONVERT(DATE, a.[Date]) AS Date_Key,

    p.Product_Key,
    pf.Platform_Key,
    c.Condition_Key,
    se.Sale_Event_Key,
    ss.Stock_Status_Key,

    DATEDIFF(
        MONTH,
        p.First_Seen_Date,
        TRY_CONVERT(DATE, a.[Date])
    ) AS Product_Age_Month,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Launch_Price_USD
    ) AS Launch_Price_USD,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Launch_Price_INR
    ) AS Launch_Price_INR,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Current_Price_USD
    ) AS Current_Price_USD,

    TRY_CONVERT(
        DECIMAL(18,2),
        a.Current_Price_INR
    ) AS Current_Price_INR,

    TRY_CONVERT(
        DECIMAL(10,2),
        a.Discount_Pct
    ) AS Discount_Pct,

    TRY_CONVERT(
        DECIMAL(4,2),
        a.Rating
    ) AS Rating,

    TRY_CONVERT(
        BIGINT,
        a.Reviews_Count
    ) AS Reviews_Count

FROM dbo.apple_products_pricing_2020_2026 a

INNER JOIN dbo.dim_product p
    ON p.Product_Category =
        LTRIM(RTRIM(a.Product_Category))
   AND p.Model_Name =
        LTRIM(RTRIM(a.Model_Name))

INNER JOIN dbo.dim_platform pf
    ON pf.Platform_Name =
        LTRIM(RTRIM(a.Platform))

INNER JOIN dbo.dim_condition c
    ON c.Condition_Name =
        LTRIM(RTRIM(a.[Condition]))

INNER JOIN dbo.dim_sale_event se
    ON se.Sale_Event_Name =
        COALESCE(
            NULLIF(LTRIM(RTRIM(a.Sale_Event)), ''),
            'None'
        )

INNER JOIN dbo.dim_stock_status ss
    ON ss.Stock_Status_Name =
        LTRIM(RTRIM(a.Stock_Status))

WHERE TRY_CONVERT(DATE, a.[Date]) IS NOT NULL;
GO

--Kiểm tra số dòng
SELECT
    (SELECT COUNT_BIG(*)
     FROM dbo.apple_products_pricing_2020_2026)
        AS Raw_Row_Count,

    (SELECT COUNT_BIG(*)
     FROM dbo.fact_price_snapshot)
        AS Fact_Row_Count;

