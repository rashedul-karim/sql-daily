-- Topic: Cross-engine table fingerprint - checking two copies of a table hold the same data
-- Database: PostgreSQL 14+ (Oracle and SQL Server equivalents below)
-- Problem: The same reference table is replicated to systems on different database
--          engines. Detect whether any copy has drifted (lost, extra or changed rows)
--          without shipping the whole table across: compare one hash per table.
-- Note: For hashes to match across engines, every engine must build exactly the same
--       string: same row order, same separators, same number and date formats, and the
--       same NULL marker. MD5 is fine for change detection; it is not a security control.
-- All data is fictional.

DROP TABLE IF EXISTS theatre_status;
CREATE TABLE theatre_status (
    sector_id       int PRIMARY KEY,
    readiness_level text NOT NULL,
    active_assets   int  NOT NULL
);
INSERT INTO theatre_status VALUES (1, 'LEVEL-2', 42), (2, 'LEVEL-3', 18), (3, 'LEVEL-1', 7);

-- Fingerprint of the whole table
SELECT count(*) AS row_count,
       md5(string_agg(sector_id || '|' || readiness_level || '|' || active_assets,
                      E'\n' ORDER BY sector_id)) AS table_md5
FROM theatre_status;

-- Simulate drift on one copy and fingerprint again: the hash changes
UPDATE theatre_status SET active_assets = 41 WHERE sector_id = 1;

SELECT count(*) AS row_count,
       md5(string_agg(sector_id || '|' || readiness_level || '|' || active_assets,
                      E'\n' ORDER BY sector_id)) AS table_md5
FROM theatre_status;

-- To find WHICH rows differ, hash per row and compare the two lists:
SELECT sector_id, md5(sector_id || '|' || readiness_level || '|' || active_assets) AS row_md5
FROM theatre_status ORDER BY sector_id;

/* Oracle 19c+ (same string, so the same MD5):
SELECT COUNT(*),
       LOWER(RAWTOHEX(STANDARD_HASH(
         LISTAGG(sector_id || '|' || readiness_level || '|' || active_assets, CHR(10))
           WITHIN GROUP (ORDER BY sector_id), 'MD5')))
FROM theatre_status;

   SQL Server 2017+:
SELECT COUNT(*),
       LOWER(CONVERT(varchar(32), HASHBYTES('MD5',
         STRING_AGG(CONVERT(varchar(max), CONCAT(sector_id, '|', readiness_level, '|', active_assets)),
                    CHAR(10)) WITHIN GROUP (ORDER BY sector_id)), 2))
FROM theatre_status;
*/

-- Expected: two different table_md5 values, before and after the update.
