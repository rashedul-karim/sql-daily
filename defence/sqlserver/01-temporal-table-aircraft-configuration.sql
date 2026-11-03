-- Topic: System-versioned temporal tables - aircraft configuration history
-- Database: SQL Server 2016+ (also Azure SQL Database)
-- Problem: Each aircraft has a fitted configuration (engine serial, radio fit, software
--          version). After an incident, investigators ask: "What exactly was fitted to
--          TR-102 at 10:00 on the day?" and "Show every change to TR-102 last month."
--          Build this so the database records history automatically, with no triggers
--          and no application code.
-- Note: SYSTEM_VERSIONING = ON makes SQL Server copy the old row to a history table on
--       every UPDATE or DELETE, stamped with the period columns (in UTC).
--       FOR SYSTEM_TIME AS OF / BETWEEN / ALL query the past directly.
--       The demo uses WAITFOR between changes so the timestamps differ.
-- All data is fictional.

SET NOCOUNT ON;

IF OBJECT_ID('dbo.aircraft_config', 'U') IS NOT NULL
BEGIN
    IF OBJECTPROPERTY(OBJECT_ID('dbo.aircraft_config'), 'TableTemporalType') = 2
        ALTER TABLE dbo.aircraft_config SET (SYSTEM_VERSIONING = OFF);
    DROP TABLE dbo.aircraft_config;
END;
DROP TABLE IF EXISTS dbo.aircraft_config_history;
GO

CREATE TABLE dbo.aircraft_config (
    tail_no        varchar(10)  NOT NULL PRIMARY KEY,
    engine_serial  varchar(20)  NOT NULL,
    radio_fit      varchar(20)  NOT NULL,
    mission_sw     varchar(10)  NOT NULL,
    valid_from     datetime2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    valid_to       datetime2(3) GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.aircraft_config_history));
GO

INSERT INTO dbo.aircraft_config (tail_no, engine_serial, radio_fit, mission_sw)
VALUES ('TR-101', 'ENG-5521', 'RAD-V2', 'SW-4.1'),
       ('TR-102', 'ENG-6610', 'RAD-V2', 'SW-4.1');

WAITFOR DELAY '00:00:01';

UPDATE dbo.aircraft_config SET mission_sw = 'SW-4.2' WHERE tail_no = 'TR-102';   -- software upgrade
DECLARE @t1 datetime2(3) = SYSUTCDATETIME();
WAITFOR DELAY '00:00:01';

UPDATE dbo.aircraft_config SET engine_serial = 'ENG-7004' WHERE tail_no = 'TR-102'; -- engine change
WAITFOR DELAY '00:00:01';

UPDATE dbo.aircraft_config SET radio_fit = 'RAD-V3' WHERE tail_no = 'TR-102';      -- radio refit

-- 1) Current configuration (normal query, no history)
SELECT tail_no, engine_serial, radio_fit, mission_sw
FROM dbo.aircraft_config;

-- 2) What was fitted at a point in time (just after the software upgrade)
SELECT tail_no, engine_serial, radio_fit, mission_sw
FROM dbo.aircraft_config FOR SYSTEM_TIME AS OF @t1
WHERE tail_no = 'TR-102';

-- 3) Full change history for one aircraft, with what changed
SELECT tail_no, engine_serial, radio_fit, mission_sw, valid_from, valid_to,
       CASE
           WHEN LAG(engine_serial) OVER (ORDER BY valid_from) <> engine_serial THEN 'Engine changed'
           WHEN LAG(radio_fit)     OVER (ORDER BY valid_from) <> radio_fit     THEN 'Radio changed'
           WHEN LAG(mission_sw)    OVER (ORDER BY valid_from) <> mission_sw    THEN 'Software changed'
           WHEN LAG(tail_no)       OVER (ORDER BY valid_from) IS NULL          THEN 'Initial fit'
       END AS change_type
FROM dbo.aircraft_config FOR SYSTEM_TIME ALL
WHERE tail_no = 'TR-102'
ORDER BY valid_from;

-- Expected: 4 rows - Initial fit, Software changed, Engine changed, Radio changed.
-- The current row has valid_to = 9999-12-31 23:59:59.999.

-- 4) While versioning is on, the history table cannot be changed with normal DML,
--    so the audit trail is tamper-resistant. Uncomment to see the error:
-- UPDATE dbo.aircraft_config_history SET radio_fit = 'X';
GO

-- Notes:
--   - Times are UTC. Convert for reports with AT TIME ZONE 'UTC' AT TIME ZONE 'Bangladesh Standard Time'.
--   - Set HISTORY_RETENTION_PERIOD (Azure SQL, SQL Server 2017+) to age out old versions.
--   - Oracle equivalent: Flashback Data Archive (FLASHBACK ARCHIVE) with AS OF TIMESTAMP.
