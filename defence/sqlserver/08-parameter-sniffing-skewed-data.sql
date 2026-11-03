-- Topic: Parameter sniffing on skewed data - diagnose and fix
-- Database: SQL Server 2016+ (notes on 2022 Parameter Sensitive Plan optimization)
-- Problem: A stored procedure returns maintenance tasks for one base. One main base owns
--          99.5% of the rows, the small detachments own a few hundred each. Whichever base
--          runs the procedure first after a restart decides the cached plan for everyone:
--          a plan built for a small detachment (index seek + key lookups) is terrible for
--          the main base, and the reverse wastes I/O on small ones.
--          Reproduce it, measure it with STATISTICS IO, and compare the standard fixes.
-- Note: SQL Server compiles a procedure once using the first parameter values it sees
--       ("sniffing") and reuses that plan. Fixes: OPTION (RECOMPILE) for rare queries,
--       OPTIMIZE FOR for a known typical value, a covering index so one plan suits all,
--       or SQL Server 2022's PSP optimization (compatibility level 160), which keeps
--       several plans per query for different parameter ranges.
-- All data is fictional.

SET NOCOUNT ON;
DROP PROCEDURE IF EXISTS dbo.get_tasks_by_base;
DROP TABLE IF EXISTS dbo.maint_tasks;
GO

CREATE TABLE dbo.maint_tasks (
    task_id    int IDENTITY PRIMARY KEY,
    base_code  varchar(10)  NOT NULL,
    tail_no    varchar(10)  NOT NULL,
    task_desc  char(200)    NOT NULL,     -- wide row, makes lookups expensive
    due_date   date         NOT NULL
);

-- 500,000 rows: 'MAIN' gets 99.5%, four detachments get 625 rows each
INSERT INTO dbo.maint_tasks (base_code, tail_no, task_desc, due_date)
SELECT CASE WHEN n % 200 = 0 THEN 'DET-' + CAST((n / 200) % 4 + 1 AS varchar(1)) ELSE 'MAIN' END,
       'TR-' + CAST(100 + n % 40 AS varchar(3)),
       'Scheduled task ' + CAST(n AS varchar(10)),
       DATEADD(DAY, n % 365, '2026-01-01')
FROM (SELECT TOP (500000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM sys.all_objects a CROSS JOIN sys.all_objects b) x;

CREATE INDEX ix_tasks_base ON dbo.maint_tasks (base_code);
GO

SELECT base_code, COUNT(*) AS task_rows
FROM dbo.maint_tasks GROUP BY base_code ORDER BY task_rows DESC;
GO

CREATE PROCEDURE dbo.get_tasks_by_base @base varchar(10)
AS
SELECT task_id, tail_no, task_desc, due_date
FROM dbo.maint_tasks
WHERE base_code = @base;
GO

SET STATISTICS IO ON;

-- 1) The problem: small base runs first, its plan is cached, then the main base reuses it
DBCC FREEPROCCACHE;    -- test servers only: clears every cached plan (needs sysadmin;
                       -- in Azure SQL use ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE)
EXEC dbo.get_tasks_by_base @base = 'DET-1';   -- seek + key lookups: about 2,000 reads
EXEC dbo.get_tasks_by_base @base = 'MAIN';    -- same plan: around 1.5 million logical reads

-- 2) Reverse order: main base first, scan plan cached, small base scans the whole table
DBCC FREEPROCCACHE;
EXEC dbo.get_tasks_by_base @base = 'MAIN';    -- clustered index scan: about 15,000 reads
EXEC dbo.get_tasks_by_base @base = 'DET-1';   -- same scan: 15,000 reads to return 625 rows
GO

-- Fix A: compile fresh every time (fine when the procedure runs rarely)
ALTER PROCEDURE dbo.get_tasks_by_base @base varchar(10)
AS
SELECT task_id, tail_no, task_desc, due_date
FROM dbo.maint_tasks
WHERE base_code = @base
OPTION (RECOMPILE);
GO
EXEC dbo.get_tasks_by_base @base = 'DET-1';   -- seek
EXEC dbo.get_tasks_by_base @base = 'MAIN';    -- scan
GO

-- Fix B: covering index, so the seek plan is good for every value (no key lookups)
ALTER PROCEDURE dbo.get_tasks_by_base @base varchar(10)
AS
SELECT task_id, tail_no, task_desc, due_date
FROM dbo.maint_tasks
WHERE base_code = @base;
GO
CREATE INDEX ix_tasks_base_cover ON dbo.maint_tasks (base_code)
    INCLUDE (tail_no, task_desc, due_date);
DBCC FREEPROCCACHE;
EXEC dbo.get_tasks_by_base @base = 'DET-1';   -- seek on the covering index
EXEC dbo.get_tasks_by_base @base = 'MAIN';    -- same seek, reads only the MAIN range
GO

SET STATISTICS IO OFF;

-- Find sniffing victims on a live server: same query, very different reads per execution
SELECT TOP (10)
       qs.execution_count,
       qs.min_logical_reads,
       qs.max_logical_reads,
       qs.max_logical_reads / NULLIF(qs.min_logical_reads, 0) AS read_ratio,
       SUBSTRING(st.text, 1, 100) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.execution_count > 1
ORDER BY read_ratio DESC;

-- Reading the numbers: the exact read counts depend on your server, but the pattern is
-- always the same: wrong-plan executions are 10x to 100x more expensive than right-plan ones.
-- Trade-offs:
--   RECOMPILE  : always the right plan, costs CPU on every call.
--   OPTIMIZE FOR (@base = 'MAIN') or OPTIMIZE FOR UNKNOWN: one stable plan, best for most calls.
--   Covering index: one plan that is good for all values, costs storage and write overhead.
--   Query Store: force a known good plan without changing code.
