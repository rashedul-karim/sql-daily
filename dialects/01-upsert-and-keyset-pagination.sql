-- Topic: Upsert and keyset pagination across PostgreSQL, Oracle and SQL Server
-- Database: PostgreSQL 16 (runnable); Oracle and SQL Server versions in comments
-- Problem: Two tasks every migration project meets:
--          1) Upsert: insert a row, or update it if the key already exists, safely
--             under concurrent sessions.
--          2) Pagination: page through a large table. OFFSET gets slower with every
--             page because the database still reads and throws away all skipped rows.
--             Keyset (seek) pagination jumps straight to the next page using an index.
-- Note: In PostgreSQL, INSERT ... ON CONFLICT is atomic and race-free.
--       MERGE in SQL Server is NOT safe under concurrency without HOLDLOCK.
--       For keyset paging, the ORDER BY must be unique, so add the primary key
--       as a tiebreaker, and use a row-value comparison (a, b) < (x, y).

DROP TABLE IF EXISTS products;
CREATE TEMP TABLE products (
    sku        text PRIMARY KEY,
    name       text,
    price      numeric(10,2),
    updated_at timestamptz DEFAULT now()
);

-- 1) UPSERT ------------------------------------------------------------------
INSERT INTO products (sku, name, price) VALUES ('A-100', 'Router', 120.00);

INSERT INTO products (sku, name, price)
VALUES ('A-100', 'Router v2', 135.00),      -- exists: update
       ('B-200', 'Switch',     80.00)       -- new: insert
ON CONFLICT (sku) DO UPDATE
   SET name       = EXCLUDED.name,
       price      = EXCLUDED.price,
       updated_at = now()
 WHERE products.price IS DISTINCT FROM EXCLUDED.price;   -- skip no-op updates

SELECT sku, name, price FROM products ORDER BY sku;

/* Oracle:
MERGE INTO products p
USING (SELECT 'A-100' sku, 'Router v2' name, 135 price FROM dual) s
   ON (p.sku = s.sku)
WHEN MATCHED THEN UPDATE SET p.name = s.name, p.price = s.price, p.updated_at = SYSTIMESTAMP
WHEN NOT MATCHED THEN INSERT (sku, name, price) VALUES (s.sku, s.name, s.price);

   SQL Server (HOLDLOCK prevents two sessions inserting the same key):
MERGE products WITH (HOLDLOCK) AS p
USING (VALUES ('A-100', 'Router v2', 135.00)) AS s (sku, name, price)
   ON p.sku = s.sku
WHEN MATCHED THEN UPDATE SET name = s.name, price = s.price, updated_at = SYSDATETIMEOFFSET()
WHEN NOT MATCHED THEN INSERT (sku, name, price) VALUES (s.sku, s.name, s.price);
*/

-- 2) PAGINATION --------------------------------------------------------------
DROP TABLE IF EXISTS audit_log;
CREATE TEMP TABLE audit_log (
    log_id    bigint PRIMARY KEY,
    logged_at timestamptz,
    action    text
);

INSERT INTO audit_log
SELECT g, now() - (g || ' seconds')::interval, 'action ' || g
FROM generate_series(1, 1000000) g;

CREATE INDEX idx_audit_time ON audit_log (logged_at DESC, log_id DESC);
VACUUM ANALYZE audit_log;

-- OFFSET: page 20,000 reads and discards 500,000 rows first
EXPLAIN ANALYZE
SELECT log_id, logged_at, action
FROM audit_log
ORDER BY logged_at DESC, log_id DESC
OFFSET 500000 LIMIT 25;

-- Keyset: the client remembers the last row it saw and seeks past it.
-- Here the last row of the previous page is taken from a subquery for the demo;
-- in an application these two values come from the previous response.
EXPLAIN ANALYZE
SELECT log_id, logged_at, action
FROM audit_log
WHERE (logged_at, log_id) < (
        SELECT logged_at, log_id FROM audit_log WHERE log_id = 500000)
ORDER BY logged_at DESC, log_id DESC
LIMIT 25;

/* Oracle 12c+:
SELECT log_id, logged_at, action FROM audit_log
WHERE logged_at < :last_time OR (logged_at = :last_time AND log_id < :last_id)
ORDER BY logged_at DESC, log_id DESC
FETCH FIRST 25 ROWS ONLY;

   SQL Server (no row-value comparison, so expand it):
SELECT TOP (25) log_id, logged_at, action FROM audit_log
WHERE logged_at < @last_time OR (logged_at = @last_time AND log_id < @last_id)
ORDER BY logged_at DESC, log_id DESC;
*/

-- Trade-off: keyset paging cannot jump to "page 731" directly. It suits infinite
-- scroll, APIs and batch extraction jobs, which is exactly what data pipelines need.
