-- Topic: Depot inventory sync with MERGE, OUTPUT $action audit and safe concurrency
-- Database: SQL Server 2016+
-- Problem: Every night the central depot sends a full snapshot of stock held at a base.
--          Sync the base's inventory table to it: insert new items, update changed
--          quantities, and mark items missing from the feed as WRITTEN-OFF (never hard
--          delete: stores records must be kept). Record every change in an audit table
--          with old and new values. The feed sometimes contains the same item twice,
--          which makes MERGE fail, so clean it first.
-- Note: MERGE errors with 8672 if a target row matches more than one source row:
--       deduplicate the source with ROW_NUMBER (keep the latest record).
--       OUTPUT $action, deleted.*, inserted.* captures the before and after of every row.
--       WITH (HOLDLOCK) stops two concurrent syncs from inserting the same key.
--       WHEN NOT MATCHED BY SOURCE handles items that disappeared from the feed.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.base_inventory;
DROP TABLE IF EXISTS dbo.depot_feed;
DROP TABLE IF EXISTS dbo.inventory_audit;
GO

CREATE TABLE dbo.base_inventory (
    item_code   varchar(12) PRIMARY KEY,
    description varchar(40) NOT NULL,
    qty         int         NOT NULL,
    status      varchar(12) NOT NULL DEFAULT 'ACTIVE',
    updated_at  datetime2(0) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.depot_feed (
    item_code   varchar(12),
    description varchar(40),
    qty         int,
    feed_time   datetime2(0)
);

CREATE TABLE dbo.inventory_audit (
    audit_id    int IDENTITY PRIMARY KEY,
    action      nvarchar(10),
    item_code   varchar(12),
    old_qty     int,
    new_qty     int,
    old_status  varchar(12),
    new_status  varchar(12),
    audited_at  datetime2(0) DEFAULT SYSDATETIME()
);

INSERT INTO dbo.base_inventory (item_code, description, qty) VALUES
    ('BRK-PAD-07', 'Brake pad set',       40),
    ('FLT-HYD-02', 'Hydraulic filter',    12),
    ('TYR-MAIN-1', 'Main wheel tyre',     18),
    ('LMP-NAV-03', 'Navigation lamp',      6);

INSERT INTO dbo.depot_feed VALUES
    ('BRK-PAD-07', 'Brake pad set',       34, '2026-10-24 01:00'),   -- qty changed
    ('FLT-HYD-02', 'Hydraulic filter',    12, '2026-10-24 01:00'),   -- unchanged
    ('TYR-MAIN-1', 'Main wheel tyre',     15, '2026-10-24 01:00'),
    ('TYR-MAIN-1', 'Main wheel tyre',     16, '2026-10-24 01:05'),   -- duplicate: keep latest
    ('SEL-CAN-01', 'Canopy seal',          4, '2026-10-24 01:00');   -- new item
    -- LMP-NAV-03 missing from the feed: write it off
GO

CREATE OR ALTER PROCEDURE dbo.sync_inventory
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;              -- any error rolls back the whole sync
    BEGIN TRANSACTION;

    WITH src AS (
        SELECT item_code, description, qty
        FROM (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY item_code ORDER BY feed_time DESC) AS rn
            FROM dbo.depot_feed
        ) d
        WHERE rn = 1
    )
    MERGE dbo.base_inventory WITH (HOLDLOCK) AS t
    USING src AS s
       ON t.item_code = s.item_code
    WHEN MATCHED AND (t.qty <> s.qty OR t.description <> s.description OR t.status <> 'ACTIVE') THEN
        UPDATE SET qty = s.qty, description = s.description,
                   status = 'ACTIVE', updated_at = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (item_code, description, qty) VALUES (s.item_code, s.description, s.qty)
    WHEN NOT MATCHED BY SOURCE AND t.status = 'ACTIVE' THEN
        UPDATE SET status = 'WRITTEN-OFF', updated_at = SYSDATETIME()
    OUTPUT $action,
           COALESCE(inserted.item_code, deleted.item_code),
           deleted.qty, inserted.qty,
           deleted.status, inserted.status
    INTO dbo.inventory_audit (action, item_code, old_qty, new_qty, old_status, new_status);

    COMMIT;
END;
GO

-- First run
EXEC dbo.sync_inventory;

SELECT item_code, description, qty, status FROM dbo.base_inventory ORDER BY item_code;
SELECT action, item_code, old_qty, new_qty, old_status, new_status
FROM dbo.inventory_audit ORDER BY audit_id;

-- Second run with the same feed: must change nothing (idempotent)
EXEC dbo.sync_inventory;
SELECT COUNT(*) AS audit_rows_after_rerun FROM dbo.inventory_audit;   -- still 4
GO

-- Expected after the first run:
--   BRK-PAD-07 34 ACTIVE      (UPDATE 40 -> 34)
--   FLT-HYD-02 12 ACTIVE      (no change, no audit row)
--   LMP-NAV-03  6 WRITTEN-OFF (UPDATE status ACTIVE -> WRITTEN-OFF)
--   SEL-CAN-01  4 ACTIVE      (INSERT)
--   TYR-MAIN-1 16 ACTIVE      (UPDATE 18 -> 16, latest of the duplicate feed rows)
--
-- Why HOLDLOCK: MERGE takes its locks row by row. Without a range lock, two sessions can
-- both find "not matched" for the same new key and both insert; one fails with a
-- primary key error. HOLDLOCK (SERIALIZABLE for this statement) closes that gap.
-- Oracle equivalent: MERGE (no NOT MATCHED BY SOURCE; use a separate UPDATE ... WHERE NOT EXISTS).
