-- Topic: Partial and covering indexes - measured with EXPLAIN (ANALYZE, BUFFERS)
-- Database: PostgreSQL 16
-- Problem: An orders table has 1 million rows, but only about 1% are 'PENDING'.
--          A dashboard repeatedly asks for pending orders of one customer, newest first.
--          Compare: no index, a full composite index, and a small partial covering index.
--          Record time, buffers read, and index size for each.
-- Note: A partial index (WHERE status = 'PENDING') stores only the rows the query needs,
--       so it is a fraction of the size. INCLUDE adds non-key columns so the query is
--       answered by an Index Only Scan without touching the table (after VACUUM sets
--       the visibility map). Always measure buffers, not just time: time varies with cache.

DROP TABLE IF EXISTS orders;
CREATE TEMP TABLE orders (
    order_id     bigint PRIMARY KEY,
    customer_id  int,
    status       text,
    created_at   timestamptz,
    amount       numeric(10,2)
);

INSERT INTO orders
SELECT g,
       (random() * 10000)::int,
       CASE WHEN random() < 0.01 THEN 'PENDING' ELSE 'SHIPPED' END,
       now() - (random() * interval '365 days'),
       round((random() * 500)::numeric, 2)
FROM generate_series(1, 1000000) g;

VACUUM ANALYZE orders;

-- The query under test
-- Run each EXPLAIN twice and record the second run (warm cache).

-- 1) No supporting index: Seq Scan over 1M rows
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, created_at, amount
FROM orders
WHERE customer_id = 42 AND status = 'PENDING'
ORDER BY created_at DESC;

-- 2) Full composite index on all rows
CREATE INDEX idx_orders_full ON orders (customer_id, status, created_at DESC);
VACUUM ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, created_at, amount
FROM orders
WHERE customer_id = 42 AND status = 'PENDING'
ORDER BY created_at DESC;

-- 3) Partial covering index: only pending rows, with the selected columns included
DROP INDEX idx_orders_full;
CREATE INDEX idx_orders_pending ON orders (customer_id, created_at DESC)
    INCLUDE (order_id, amount)
    WHERE status = 'PENDING';
VACUUM ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, created_at, amount
FROM orders
WHERE customer_id = 42 AND status = 'PENDING'
ORDER BY created_at DESC;

-- Compare index sizes
CREATE INDEX idx_orders_full ON orders (customer_id, status, created_at DESC);
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Measured on PostgreSQL 16 (your numbers will differ slightly):
--   no index        : Seq Scan,        8,334 buffers, ~39 ms
--   full composite  : Index Scan,          5 buffers, ~0.03 ms, index 39 MB
--   partial covering: Index Only Scan,     3 buffers, ~0.02 ms, index 504 kB
-- Same speed as the full index at about 1/80th of the size.
--
-- Trade-off: the partial index only helps queries whose WHERE clause implies
-- status = 'PENDING'. Write-heavy tables pay for every extra index on INSERT/UPDATE.
--
-- Dialects: SQL Server calls these filtered indexes (CREATE INDEX ... WHERE ...)
-- and also supports INCLUDE. Oracle has no partial index; the usual workaround is a
-- function-based index that returns NULL for unwanted rows, since NULL keys are not indexed.
