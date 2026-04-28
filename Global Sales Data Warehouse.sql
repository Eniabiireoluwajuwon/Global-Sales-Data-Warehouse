-- PROJECT: Global Sales Data Warehouse Build
-- PURPOSE: Transform a messy flat CSV into a clean, optimized Star Schema

-- DATABASE SETUP
-- Start fresh. If the database already exists from a previous run, nuke it and rebuild.
DROP DATABASE IF EXISTS `Global_Sales`;
CREATE DATABASE `Global_Sales`;
USE `Global_Sales`;

-- Just taking a quick peek at the raw, dirty data before we start the ETL pipeline
SELECT * FROM global_sales_data;


-- THE MEDALLION ARCHITECTURE (SILVER & GOLD LAYERS)
-- We use a VIEW here so we don't permanently destroy or alter the original raw table.

CREATE OR REPLACE VIEW Global_Sales.gold_global_sales_data AS

-- The "Silver" Layer: This is the data scrubber. We handle all text cleaning here.
WITH Clean_Text_Step AS (
    SELECT 
        -- Strip out the annoying '$' and ',' from the prices so we can actually do math on them later.
        -- After stripping, if it's an empty string, force it into a true SQL NULL.
        NULLIF(TRIM(REPLACE(REPLACE(Price, '$', ''), ',', '')), '') AS Raw_Price,
        
        -- Fix the known typos in the category column so our BI tools group things correctly
        NULLIF(
            CASE 
                WHEN TRIM(Category) = 'Electronic' THEN 'Electronics'
                WHEN TRIM(Category) = 'Office Supplie' THEN 'Office Supplies'
                ELSE TRIM(Category) 
            END, 
        '') AS Clean_Category,
        
        -- Standardize casing so 'JOHN' and 'john' aren't accidentally counted as two different people
        NULLIF(UPPER(TRIM(Customer_Name)), '') AS Clean_Customer_Name,
        
        -- Basic cleanup for the rest of the text columns (trimming invisible spaces)
        NULLIF(TRIM(Customer_Email), '') AS Clean_Customer_Email,
        NULLIF(TRIM(Customer_City), '') AS Clean_Customer_City,
        NULLIF(TRIM(Product_Name), '') AS Clean_Product_Name,
        NULLIF(UPPER(TRIM(Manager_Name)), '') AS Clean_Manager_Name,
        NULLIF(TRIM(Store_Name), '') AS Clean_Store_Name,
        NULLIF(TRIM(Store_City), '') AS Clean_Store_City,
        NULLIF(TRIM(Order_ID), '') AS Clean_Order_ID,
        NULLIF(TRIM(Date), '') AS Clean_Date,
        NULLIF(TRIM(Quantity), '') AS Clean_Quantity 
        
    FROM Global_Sales.global_sales_data
),

-- The "Gold" Layer: The text is clean, now we apply strict business rules and data types
Business_Ready_Step AS (
    SELECT
        Clean_Order_ID,
        Clean_Date,
        Clean_Customer_Name,
        Clean_Customer_Email,
        Clean_Customer_City,
        Clean_Product_Name,
        Clean_Category,
        Clean_Manager_Name,
        Clean_Store_Name,
        Clean_Store_City,
        Clean_Quantity,
        
        -- Safely cast the scrubbed string into a precise financial decimal
        CAST(Raw_Price AS DECIMAL(25, 2)) AS Clean_Price
        
    FROM Clean_Text_Step
    
    -- The Bouncer: If any of these critical columns are NULL, drop the row entirely.
    -- We don't want partial/broken data messing up our downstream analytics.
    WHERE Clean_Order_ID IS NOT NULL
      AND Clean_Date IS NOT NULL
      AND Clean_Customer_Name IS NOT NULL
      AND Clean_Customer_Email IS NOT NULL
      AND Clean_Customer_City IS NOT NULL
      AND Clean_Product_Name IS NOT NULL
      AND Clean_Category IS NOT NULL
      AND Clean_Manager_Name IS NOT NULL
      AND Clean_Store_Name IS NOT NULL
      AND Clean_Store_City IS NOT NULL
      AND Clean_Quantity IS NOT NULL
)

-- Spit out the final, pristine data
SELECT * FROM Business_Ready_Step;

-- Let's check our work to make sure the View is working perfectly
SELECT * FROM global_sales.gold_global_sales_data;


-- 3. DIMENSIONAL MODELING (BUILDING THE STAR SCHEMA)
-- Breaking the flat file into smaller, efficient Dimension tables (The Nouns)


-- --- CUSTOMER DIMENSION ---
CREATE TABLE Customers (
  Customer_ID INT NOT NULL AUTO_INCREMENT,
  Customer_Name varchar(50) NOT NULL,
  Customer_Email varchar(50) NOT NULL,
  Customer_City varchar(50) NOT NULL,
  PRIMARY KEY (Customer_ID)
);

-- We use GROUP BY instead of DISTINCT here to avoid Cartesian explosions (Fan-Outs). 
-- If a customer has messy data with multiple cities tied to their email, MAX() safely forces it down to one row.
INSERT INTO Customers (Customer_Name, Customer_Email, Customer_City)
SELECT 
    MAX(Clean_Customer_Name), 
    Clean_Customer_Email, 
    MAX(Clean_Customer_City)
FROM global_sales.gold_global_sales_data
GROUP BY Clean_Customer_Email;

-- --- PRODUCT DIMENSION ---
CREATE TABLE Products (
  Product_ID INT NOT NULL AUTO_INCREMENT,
  Product_Name varchar(50) NOT NULL,
  Category varchar(50) NOT NULL,
  Price INT NOT NULL,
  PRIMARY KEY (Product_ID)
);

INSERT INTO Products (Product_Name, Category, Price)
SELECT
    Clean_Product_Name, 
    MAX(Clean_Category), 
    MAX(Clean_Price)
FROM global_sales.gold_global_sales_data
GROUP BY Clean_Product_Name;

-- --- STORE DIMENSION ---
CREATE TABLE Stores (
  Store_ID INT NOT NULL AUTO_INCREMENT,
  Store_Name varchar(50) NOT NULL,
  Store_City varchar(50) NOT NULL,
  Manager_Name varchar(50) NOT NULL,
  PRIMARY KEY (Store_ID)
);

INSERT INTO Stores (Store_Name, Store_City, Manager_Name)
SELECT
    Clean_Store_Name, 
    MAX(Clean_Store_City), 
    MAX(Clean_Manager_Name)
FROM global_sales.gold_global_sales_data
GROUP BY Clean_Store_Name;



-- 4. THE FACT TABLE (THE HUB)
-- This table only holds math (Verbs) and IDs pointing to the Dimensions. No heavy text!

CREATE TABLE Transactions (
    Order_ID INT PRIMARY KEY,
    Date DATETIME NOT NULL,
    Quantity INT NOT NULL,
    
    -- Buckets to hold the IDs
    Customer_ID INT,
    Product_ID INT,
    Store_ID INT,
    
    -- Enforcing the rules: These IDs MUST exist in the dimension tables above
    FOREIGN KEY (Customer_ID) REFERENCES Customers(Customer_ID),
    FOREIGN KEY (Product_ID) REFERENCES Products(Product_ID),
    FOREIGN KEY (Store_ID) REFERENCES Stores(Store_ID)
);

-- The Grand Finale: Pipe the order data in, and use LEFT JOINS to magically 
-- swap the text names for our new, hyper-efficient ID numbers.
INSERT INTO Transactions (Order_ID, Date, Quantity, customer_id, product_id, store_id)
SELECT  
    gold.Clean_Order_ID, 
    gold.Clean_Date, 
    gold.Clean_Quantity, 
    c.customer_id,   
    p.product_id,    
    s.store_id       
FROM global_sales.gold_global_sales_data gold
-- Match the clean text to the dimension tables to grab the generated IDs
LEFT JOIN customers c ON gold.Clean_Customer_Email = c.Customer_Email
LEFT JOIN products p  ON gold.Clean_Product_Name = p.Product_Name
LEFT JOIN stores s    ON gold.Clean_Store_Name = s.Store_Name;

-- Moment of truth: Look at the beautiful, number-only Star Schema Fact table
SELECT *
FROM global_sales.transactions
LIMIT 10;