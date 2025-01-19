-- SQL-скрипт для создания OLAP-схемы (Snowflake Schema)

-- 1. Таблица размерности: Dim_Product
CREATE TABLE Dim_Product (
    ProductID SERIAL PRIMARY KEY,
    ProductName VARCHAR(255) NOT NULL,
    Category VARCHAR(100),
    Brand VARCHAR(100),
    StartDate DATE NOT NULL,
    EndDate DATE,
    IsCurrent BOOLEAN NOT NULL
);

-- 2. Таблица размерности: Dim_Time
CREATE TABLE Dim_Time (
    DateID SERIAL PRIMARY KEY,
    FullDate DATE NOT NULL,
    Month INT NOT NULL,
    Year INT NOT NULL
);

-- 3. Таблица размерности: Dim_Customer
CREATE TABLE Dim_Customer (
    CustomerID BIGINT PRIMARY KEY,
    FullName VARCHAR(255) NOT NULL,
    Address TEXT,
    Phone VARCHAR(15),
    Email VARCHAR(255),
    RegistrationDate DATE
);

-- 4. Таблица фактов: Fact_Sales
CREATE TABLE Fact_Sales (
    SaleID SERIAL PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Dim_Product(ProductID),
    DateID INT NOT NULL REFERENCES Dim_Time(DateID),
    CustomerID BIGINT NOT NULL REFERENCES Dim_Customer(CustomerID),
    QuantitySold INT NOT NULL,
    TotalRevenue DECIMAL(10, 2) NOT NULL
);

-- 5. Таблица фактов: Fact_Orders
CREATE TABLE Fact_Orders (
    OrderID SERIAL PRIMARY KEY,
    CustomerID BIGINT NOT NULL REFERENCES Dim_Customer(CustomerID),
    DateID INT NOT NULL REFERENCES Dim_Time(DateID),
    TotalItems INT NOT NULL,
    TotalOrderValue DECIMAL(10, 2) NOT NULL,
    PaymentMethod VARCHAR(50),
    ShipperID INT
);

-- ETL-процесс: Перенос данных из OLTP в OLAP

-- 1. Загрузка данных в таблицу размерности Dim_Time
ALTER TABLE dim_time ADD CONSTRAINT unique_fulldate UNIQUE (FullDate);

INSERT INTO dim_time (FullDate, Month, Year)
SELECT DISTINCT
    CAST(o."OrderDate" AS DATE) AS FullDate,
    EXTRACT(MONTH FROM o."OrderDate") AS Month,
    EXTRACT(YEAR FROM o."OrderDate") AS Year
FROM "Orders" o
ON CONFLICT (FullDate) DO NOTHING;

-- 2. Загрузка данных в таблицу размерности Dim_Customer
INSERT INTO dim_customer (CustomerID, FullName, Address, Phone, Email, RegistrationDate)
SELECT DISTINCT
    u."UserID" AS CustomerID,
    u."FullName",
    u."Address",
    u."Phone",
    u."Email",
    u."RegistrationDate"
FROM "Users" u
ON CONFLICT (CustomerID) DO NOTHING;

-- 3. Загрузка данных в таблицу размерности Dim_Product
ALTER TABLE dim_product ADD CONSTRAINT unique_product_combination UNIQUE (ProductID, ProductName, Category, Brand);

INSERT INTO dim_product (ProductID, ProductName, Category, Brand, StartDate, EndDate, IsCurrent)
SELECT DISTINCT
    p."ProductID",
    p."ProductName",
    c."CategoryName" AS Category,
    b."BrandName" AS Brand,
    CURRENT_DATE AS StartDate,
    CAST(NULL AS DATE) AS EndDate, -- Явное преобразование NULL в тип DATE
    TRUE AS IsCurrent
FROM "Products" p
JOIN "Categories" c ON p."CategoryID" = c."CategoryID"
JOIN "Brands" b ON p."BrandID" = b."BrandID"
ON CONFLICT (ProductID) DO NOTHING;

-- 4. Загрузка данных в таблицу фактов Fact_Sales
INSERT INTO fact_sales (ProductID, DateID, CustomerID, QuantitySold, TotalRevenue)
SELECT 
    oi."ProductID",
    dt.dateid, -- Используем имя в нижнем регистре
    o."UserID" AS CustomerID,
    SUM(oi."Quantity") AS QuantitySold,
    SUM(oi."Quantity" * oi."Price") AS TotalRevenue
FROM "Order_Items" oi
JOIN "Orders" o ON oi."OrderID" = o."OrderID"
JOIN Dim_Time dt ON dt.fulldate = CAST(o."OrderDate" AS DATE)
GROUP BY oi."ProductID", dt.dateid, o."UserID";


-- 5. Загрузка данных в таблицу фактов Fact_Orders
INSERT INTO fact_orders (OrderID, CustomerID, DateID, TotalItems, TotalOrderValue, PaymentMethod, ShipperID)
SELECT 
    o."OrderID",
    o."UserID" AS CustomerID,
    dt.dateid, -- Используем имя колонки в нижнем регистре
    COUNT(oi."OrderItemID") AS TotalItems,
    SUM(oi."Quantity" * oi."Price") AS TotalOrderValue,
    o."PaymentMethod",
    o."ShipperID"
FROM "Orders" o
JOIN "Order_Items" oi ON o."OrderID" = oi."OrderID"
JOIN Dim_Time dt ON dt.fulldate = CAST(o."OrderDate" AS DATE) 
GROUP BY o."OrderID", o."UserID", dt.dateid, o."PaymentMethod", o."ShipperID";
