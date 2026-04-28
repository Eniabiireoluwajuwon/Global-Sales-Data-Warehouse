# 🏢 Global Sales Data Warehouse: End-to-End ETL & Star Schema

## 📌 Project Overview
This project demonstrates a complete Data Engineering pipeline, transforming a chaotic, 12-column flat file (CSV) into a fully optimized, enterprise-grade **Star Schema Data Warehouse**. 

The objective was to ingest raw sales data, clean and standardize the text, enforce data types, and normalize the database architecture to eliminate redundant text storage and prepare the data for massive BI aggregations.

##  Tech Stack
* **SQL Dialect:** MySQL / Relational Database Management Systems (RDBMS)
* **Core Concepts:** ETL Pipelines, Medallion Architecture, Dimensional Modeling (Star Schema), Data Normalization, Referential Integrity.

# Architecture & Pipeline Phases

### Phase 1: The Medallion Architecture (ETL)
Instead of permanently altering the raw database, I engineered a dynamic pipeline using **Common Table Expressions (CTEs)** wrapped inside a `VIEW`.
* **Bronze Layer:** The raw, ingested CSV containing dirty data (hidden whitespaces, casing inconsistencies, formatted financial strings, and missing values).
* **Silver Layer (Scrubber):** Utilized String Functions (`TRIM`, `UPPER`, `REPLACE`) and `CASE` statements to standardize categorical text, catch invisible whitespaces, and dynamically handle rogue `NULL` values.
* **Gold Layer (Business Ready):** Safely cast financial strings into precise `DECIMAL` types and applied strict filtering to drop rows missing critical operational data.

### Phase 2: Dimensional Modeling (Normalization)
To optimize storage and performance, the cleaned flat file was broken down into a **Star Schema** using `GROUP BY` aggregations to prevent Cartesian explosions (Fan-Outs).
* `Customers` Dimension: Deduplicated by Email.
* `Products` Dimension: Deduplicated by Product Name.
* `Stores` Dimension: Deduplicated by Store Name.

### Phase 3: The Fact Table (The Hub)
The central `Transactions` table was built to hold only the mathematical metrics (Verbs) and ID numbers. 
* Enforced strict database rules using `AUTO_INCREMENT` Primary Keys and Foreign Key constraints.
* Executed an `INSERT INTO ... SELECT` statement with targeted `LEFT JOINS` to map the cleaned textual data to their respective ID numbers.

## 🧠 Key SQL Techniques Demonstrated
* `CREATE OR REPLACE VIEW` for non-destructive data transformations.
* Advanced text manipulation (`REPLACE`, `TRIM`, `UPPER`).
* Conditional logic (`CASE WHEN`) for on-the-fly data correction.
* `GROUP BY` for safe Dimension table extraction.
* Table creation with strict `PRIMARY KEY` and `FOREIGN KEY` referential integrity.
* `LEFT JOIN` mapping to translate text strings into optimized integers.

## 🚀 How to Run This Project
1. Execute the `Global_Sales_Messy.csv` import into your RDBMS as `global_sales_data`.
2. Run the provided `Global_Sales_Data_Warehouse_Build.sql` script sequentially.
3. The script will automatically drop/create the database, build the Silver/Gold views, generate the Dimension tables, and populate the central Fact table. 
4. Run `SELECT * FROM global_sales.transactions LIMIT 10;` to view the finalized, number-only Star Schema.
