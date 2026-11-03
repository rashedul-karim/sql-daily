-- Topic: Row-Level Security - each unit sees only its own maintenance records
-- Database: SQL Server 2016+ (also Azure SQL Database)
-- Problem: Several squadrons share one maintenance database. A squadron's staff must see
--          and change only their own work orders; HQ quality assurance sees everything
--          but cannot edit. The application uses one pooled login and passes the real
--          user's unit through SESSION_CONTEXT. Users must not be able to bypass the
--          rule with ad-hoc queries, and must not be able to move a record to another unit.
-- Note: RLS = an inline table-valued function (the predicate) + a SECURITY POLICY that
--       binds it to the table. FILTER predicates hide rows from SELECT/UPDATE/DELETE;
--       BLOCK predicates stop writes that would create rows outside the user's scope.
--       SESSION_CONTEXT with @read_only = 1 cannot be changed later in the session.
--       The demo uses database users WITHOUT LOGIN and EXECUTE AS to switch identity.
-- All data is fictional.

SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'unit_policy')
    DROP SECURITY POLICY sec.unit_policy;
DROP FUNCTION IF EXISTS sec.fn_unit_predicate;
DROP FUNCTION IF EXISTS sec.fn_unit_write_predicate;
DROP TABLE IF EXISTS dbo.work_orders;
IF USER_ID('app_user') IS NOT NULL DROP USER app_user;
IF SCHEMA_ID('sec') IS NOT NULL DROP SCHEMA sec;
GO
CREATE SCHEMA sec;
GO

CREATE TABLE dbo.work_orders (
    wo_id      int          PRIMARY KEY,
    unit       varchar(10)  NOT NULL,
    tail_no    varchar(10)  NOT NULL,
    task       varchar(60)  NOT NULL,
    status     varchar(10)  NOT NULL
);

INSERT INTO dbo.work_orders VALUES
    (1, 'SQN-A', 'TR-101', 'Brake unit replacement', 'OPEN'),
    (2, 'SQN-A', 'TR-102', '100-hour inspection',    'CLOSED'),
    (3, 'SQN-B', 'TR-201', 'Radio fault isolation',  'OPEN'),
    (4, 'SQN-B', 'TR-202', 'Canopy seal change',     'OPEN');

CREATE USER app_user WITHOUT LOGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.work_orders TO app_user;
GO

-- Predicate: rows visible when unit matches the session, or the session is HQ-QA
CREATE FUNCTION sec.fn_unit_predicate (@unit varchar(10))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS allowed
    WHERE @unit = CAST(SESSION_CONTEXT(N'unit') AS varchar(10))
       OR CAST(SESSION_CONTEXT(N'unit') AS varchar(10)) = 'HQ-QA';
GO

-- Separate write predicate: HQ-QA is read-only, units can only write their own rows
CREATE FUNCTION sec.fn_unit_write_predicate (@unit varchar(10))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS allowed
    WHERE @unit = CAST(SESSION_CONTEXT(N'unit') AS varchar(10));
GO

CREATE SECURITY POLICY sec.unit_policy
    ADD FILTER PREDICATE sec.fn_unit_predicate(unit)       ON dbo.work_orders,
    ADD BLOCK  PREDICATE sec.fn_unit_write_predicate(unit) ON dbo.work_orders AFTER INSERT,
    ADD BLOCK  PREDICATE sec.fn_unit_write_predicate(unit) ON dbo.work_orders AFTER UPDATE,
    ADD BLOCK  PREDICATE sec.fn_unit_write_predicate(unit) ON dbo.work_orders BEFORE UPDATE,
    ADD BLOCK  PREDICATE sec.fn_unit_write_predicate(unit) ON dbo.work_orders BEFORE DELETE
WITH (STATE = ON);
GO

-- Squadron A technician
EXECUTE AS USER = 'app_user';
EXEC sp_set_session_context @key = N'unit', @value = 'SQN-A';
SELECT wo_id, unit, tail_no, task, status FROM dbo.work_orders;     -- rows 1, 2 only

UPDATE dbo.work_orders SET status = 'CLOSED' WHERE wo_id = 3;       -- 0 rows: invisible
SELECT @@ROWCOUNT AS rows_updated;

BEGIN TRY
    UPDATE dbo.work_orders SET unit = 'SQN-B' WHERE wo_id = 1;      -- move out of scope
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS err, 'Blocked: cannot move a record to another unit' AS result;
END CATCH;
REVERT;
GO

-- HQ quality assurance: sees all, cannot edit
EXECUTE AS USER = 'app_user';
EXEC sp_set_session_context @key = N'unit', @value = 'HQ-QA', @read_only = 1;
SELECT wo_id, unit, tail_no, task, status FROM dbo.work_orders;     -- all 4 rows

BEGIN TRY
    UPDATE dbo.work_orders SET status = 'CLOSED' WHERE wo_id = 4;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS err, 'Blocked: QA is read-only' AS result;
END CATCH;

-- read_only = 1: trying to switch unit fails for the rest of this session
BEGIN TRY
    EXEC sp_set_session_context @key = N'unit', @value = 'SQN-A';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS err, 'Blocked: session unit is locked' AS result;
END CATCH;
REVERT;
GO

-- Expected: SQN-A sees 2 rows, its update of row 3 affects 0 rows, moving row 1 to
-- SQN-B fails (error 33504, block predicate). HQ-QA sees 4 rows and its update fails
-- with the same error. Changing a read-only session key fails.
--
-- To rerun, open a new session: the read-only 'unit' key stays locked for this one.
--
-- Points to remember:
--   - Members of db_owner and sysadmin are still subject to the policy unless they disable it.
--   - Keep predicate functions simple: they run for every row and are inlined into plans.
--   - Oracle equivalent: Virtual Private Database (DBMS_RLS). PostgreSQL: CREATE POLICY.
