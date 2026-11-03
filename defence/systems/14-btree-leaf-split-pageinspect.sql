-- Topic: B-Tree leaf page split and index fragmentation analysis with pageinspect
-- Database: PostgreSQL 14+ with pageinspect extension
-- Problem: Monotonic integer sequences vs Random UUID primary keys behave drastically differently
--          under heavy concurrent insert loads. Use low-level page inspection to contrast 50/50 page
--          splits and heap fragmentation.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS test_index_fragmentation (
    id BIGINT PRIMARY KEY,
    payload TEXT
);

INSERT INTO test_index_fragmentation
SELECT i, repeat('X', 100) FROM generate_series(1, 1000) i
ON CONFLICT (id) DO NOTHING;

-- Query index page density and leaf count
SELECT relname, relpages, reltuples
FROM pg_class
WHERE relname IN ('test_index_fragmentation', 'test_index_fragmentation_pkey');
