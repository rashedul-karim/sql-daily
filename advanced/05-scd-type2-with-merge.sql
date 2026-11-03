-- Topic: Slowly Changing Dimension Type 2 load with MERGE
-- Database: PostgreSQL 16 (MERGE needs 15+)
-- Problem: A nightly extract delivers the current state of customers. Keep full history:
--          when a tracked attribute changes, close the old row (valid_to, is_current = false)
--          and insert a new current row. New customers get inserted. Unchanged rows are untouched.
--          Running the same load twice must not create duplicates (idempotent).
-- Note: A single MERGE cannot both update a matched row AND insert its replacement.
--       Standard trick: step 1 MERGE closes changed rows and inserts brand-new keys;
--       step 2 inserts new versions for keys that no longer have a current row.
--       IS DISTINCT FROM compares safely when values can be NULL.

DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS stg_customer;

CREATE TEMP TABLE dim_customer (
    customer_sk  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  int,
    city         text,
    tier         text,
    valid_from   date,
    valid_to     date,
    is_current   boolean
);

CREATE TEMP TABLE stg_customer (
    customer_id int,
    city        text,
    tier        text
);

-- Existing history
INSERT INTO dim_customer (customer_id, city, tier, valid_from, valid_to, is_current) VALUES
    (101, 'Dhaka',      'Silver', '2025-01-01', NULL, true),
    (102, 'Chattogram', 'Gold',   '2025-01-01', NULL, true),
    (103, 'Sylhet',     NULL,     '2025-01-01', NULL, true);

-- Tonight's extract: 101 moved, 102 unchanged, 103 got a tier, 104 is new
INSERT INTO stg_customer VALUES
    (101, 'Khulna',     'Silver'),
    (102, 'Chattogram', 'Gold'),
    (103, 'Sylhet',     'Bronze'),
    (104, 'Rajshahi',   'Silver');

-- Run the load inside a transaction so a failure leaves the dimension untouched
BEGIN;

-- Step 1: close changed rows, insert brand-new customers
MERGE INTO dim_customer d
USING stg_customer s
   ON d.customer_id = s.customer_id AND d.is_current
WHEN MATCHED AND (d.city IS DISTINCT FROM s.city OR d.tier IS DISTINCT FROM s.tier) THEN
    UPDATE SET valid_to = CURRENT_DATE - 1, is_current = false
WHEN NOT MATCHED THEN
    INSERT (customer_id, city, tier, valid_from, valid_to, is_current)
    VALUES (s.customer_id, s.city, s.tier, CURRENT_DATE, NULL, true);

-- Step 2: new current version for every customer just closed in step 1
INSERT INTO dim_customer (customer_id, city, tier, valid_from, valid_to, is_current)
SELECT s.customer_id, s.city, s.tier, CURRENT_DATE, NULL, true
FROM stg_customer s
WHERE NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE d.customer_id = s.customer_id AND d.is_current
);

COMMIT;

SELECT customer_id, city, tier, valid_from, valid_to, is_current
FROM dim_customer
ORDER BY customer_id, valid_from;

-- Idempotency check: run BEGIN ... COMMIT again and the row count must stay the same.
-- Expected: 101 and 103 have 2 rows each (old closed, new current), 102 has 1, 104 has 1.

-- Dialects: SQL Server and Oracle both support MERGE with the same two-step pattern.
-- In Databricks, MERGE INTO a Delta table is the standard way to build SCD2.
