-- Topic: Interval partitioning for flight telemetry - pruning, local indexes, purging
-- Database: Oracle 19c+ Enterprise Edition, or Oracle Database 23ai Free
--           (both include the Partitioning option)
-- Problem: Engine sensors write readings every few seconds. The table grows by millions
--          of rows a month; most queries ask about one aircraft over a few days, and data
--          older than 12 months must be purged. Design the table so that:
--          1) new monthly partitions are created automatically,
--          2) date-range queries read only the relevant partitions (partition pruning),
--          3) old months are removed instantly without a huge DELETE.
-- Note: INTERVAL (NUMTOYMINTERVAL(1, 'MONTH')) creates a partition the first time a row
--       for a new month arrives. A LOCAL index is partitioned the same way as the table,
--       so dropping a partition does not invalidate it. Check pruning in the plan:
--       Pstart/Pstop show which partitions are read.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE engine_telemetry PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE engine_telemetry (
    tail_no     VARCHAR2(10)  NOT NULL,
    read_at     TIMESTAMP     NOT NULL,
    egt_c       NUMBER(5,1),          -- exhaust gas temperature
    rpm_pct     NUMBER(5,2),
    oil_psi     NUMBER(5,1)
)
PARTITION BY RANGE (read_at)
INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
(PARTITION p_before_2026 VALUES LESS THAN (TIMESTAMP '2026-01-01 00:00:00'));

CREATE INDEX ix_telemetry_tail_time ON engine_telemetry (tail_no, read_at) LOCAL;

-- About 10 months of readings for 4 aircraft (one row per aircraft every 10 minutes)
INSERT /*+ APPEND */ INTO engine_telemetry
SELECT 'TR-10' || MOD(LEVEL, 4),
       TIMESTAMP '2026-01-01 00:00:00' + NUMTODSINTERVAL(LEVEL * 150, 'SECOND'),
       600 + MOD(LEVEL, 50),
       85  + MOD(LEVEL, 10),
       60  + MOD(LEVEL, 7)
FROM dual CONNECT BY LEVEL <= 170000;
COMMIT;

BEGIN DBMS_STATS.GATHER_TABLE_STATS(USER, 'ENGINE_TELEMETRY'); END;
/

-- 1) Partitions were created automatically, one per month
SELECT partition_name, high_value, num_rows
FROM user_tab_partitions
WHERE table_name = 'ENGINE_TELEMETRY'
ORDER BY partition_position;

-- 2) Partition pruning: a 3-day window touches one partition only
EXPLAIN PLAN FOR
SELECT tail_no, MAX(egt_c) AS max_egt, AVG(oil_psi) AS avg_oil
FROM engine_telemetry
WHERE tail_no = 'TR-102'
  AND read_at >= TIMESTAMP '2026-08-10 00:00:00'
  AND read_at <  TIMESTAMP '2026-08-13 00:00:00'
GROUP BY tail_no;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +PARTITION'));
-- Look for PARTITION RANGE SINGLE with the same Pstart and Pstop.

-- Pruning is lost when the partition key is wrapped in a function:
EXPLAIN PLAN FOR
SELECT COUNT(*)
FROM engine_telemetry
WHERE TRUNC(CAST(read_at AS DATE), 'MM') = DATE '2026-08-01';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +PARTITION'));
-- Shows PARTITION RANGE ALL: every month is scanned.

-- 3) Purge the oldest month instantly (metadata operation, no row-by-row DELETE)
--    PARTITION FOR (...) names the partition by a value inside it, since interval
--    partitions get system names like SYS_P1234.
ALTER TABLE engine_telemetry
    DROP PARTITION FOR (TIMESTAMP '2026-01-15 00:00:00')
    UPDATE INDEXES;

SELECT COUNT(*) AS partitions_left
FROM user_tab_partitions
WHERE table_name = 'ENGINE_TELEMETRY';

-- Production notes:
--   - Schedule the purge as a job that drops partitions older than 12 months.
--   - Compress older partitions (ALTER TABLE ... MOVE PARTITION ... COMPRESS) to save space.
--   - SQL Server equivalent: partition function + scheme, with SWITCH or TRUNCATE ... WITH
--     (PARTITIONS (n)) for purging; new partitions must be added with SPLIT, not automatically.
