-- Topic: Checking a PostgreSQL database for page and index corruption
-- Database: PostgreSQL 14+ (amcheck extension, ships with PostgreSQL)
-- Problem: After a power loss or a storage fault, a DBA must find out whether any table
--          or index pages are damaged before trusting the data. Torn (partially written)
--          pages are caught by data checksums; damaged index structure is caught by amcheck.
-- Note: Data checksums are set at initdb time (initdb --data-checksums) or enabled offline
--       with pg_checksums. Oracle's equivalents are DB_BLOCK_CHECKSUM and RMAN VALIDATE;
--       SQL Server uses PAGE_VERIFY CHECKSUM and DBCC CHECKDB.
-- All data is fictional.

CREATE EXTENSION IF NOT EXISTS amcheck;

-- 1) Are data checksums on? If not, torn pages can go unnoticed.
SHOW data_checksums;

-- 2) Checksum failures recorded since statistics were last reset (PostgreSQL 12+)
SELECT datname, checksum_failures, checksum_last_failure
FROM pg_stat_database
WHERE datname = current_database();

-- 3) Structural check of every B-tree index in this database
DROP TABLE IF EXISTS sortie_log;
CREATE TABLE sortie_log (sortie_id int PRIMARY KEY, tail_no text, flown_on date);
CREATE INDEX ON sortie_log (tail_no, flown_on);
INSERT INTO sortie_log
SELECT g, 'TR-' || (100 + g % 20), date '2026-01-01' + g % 300
FROM generate_series(1, 50000) g;

-- List the B-tree indexes first (MATERIALIZED), then check each one. This makes sure
-- bt_index_check is only ever called on indexes, whatever order the planner picks.
WITH btree_indexes AS MATERIALIZED (
    SELECT c.oid, c.relname
    FROM pg_index i
    JOIN pg_class c     ON c.oid = i.indexrelid
    JOIN pg_am am       ON am.oid = c.relam AND am.amname = 'btree'
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
      AND c.relpersistence <> 't'
      AND i.indisready AND i.indisvalid
)
SELECT b.relname                                  AS index_name,
       pg_size_pretty(pg_relation_size(b.oid))    AS size,
       'OK'                                       AS result
FROM btree_indexes b
CROSS JOIN LATERAL (SELECT bt_index_check(b.oid::regclass, true)) chk  -- raises an error if corrupt
ORDER BY b.relname;

-- Expected: data_checksums shows on or off (it depends on how the cluster was created);
-- checksum_failures is 0 when checksums are on and empty when they are off; every index,
-- including the two on sortie_log, shows OK. A corrupt index stops the query with an error
-- that names the index and the damaged block.
-- bt_index_check takes only a light lock; bt_index_parent_check is more thorough
-- but blocks writes, so run it in a maintenance window.
