-- Topic: Ingesting nested JSON debrief records with OPENJSON
-- Database: SQL Server 2016+ (JSON functions need compatibility level 130+)
-- Problem: A new debrief app sends each training sortie as one JSON document: header
--          fields, a nested crew array, and a nested array of defects raised. Load it into
--          three relational tables (sortie, crew, defects), reject malformed documents
--          into a quarantine table instead of failing the batch, and finally produce JSON
--          back out for a downstream API.
-- Note: OPENJSON ... WITH (...) maps JSON paths to typed columns. A nested array is read
--       with AS JSON, then CROSS APPLY OPENJSON on it again. ISJSON() filters bad input.
--       'strict' in a path raises an error when a required field is missing; the default
--       'lax' mode returns NULL instead. FOR JSON PATH builds JSON from rows.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.debrief_defects;
DROP TABLE IF EXISTS dbo.debrief_crew;
DROP TABLE IF EXISTS dbo.debrief_sortie;
DROP TABLE IF EXISTS dbo.debrief_raw;
DROP TABLE IF EXISTS dbo.debrief_quarantine;
GO

CREATE TABLE dbo.debrief_raw (
    raw_id    int IDENTITY PRIMARY KEY,
    payload   nvarchar(max) NOT NULL,
    received  datetime2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.debrief_sortie (
    sortie_id   varchar(12) PRIMARY KEY,
    tail_no     varchar(10) NOT NULL,
    flown_on    date        NOT NULL,
    flight_hrs  decimal(4,2) NOT NULL,
    profile     varchar(20) NULL
);

CREATE TABLE dbo.debrief_crew (
    sortie_id  varchar(12) REFERENCES dbo.debrief_sortie,
    service_no varchar(12),
    crew_role  varchar(12)
);

CREATE TABLE dbo.debrief_defects (
    sortie_id  varchar(12) REFERENCES dbo.debrief_sortie,
    fault_code varchar(10),
    severity   varchar(10),
    note       nvarchar(200)
);

CREATE TABLE dbo.debrief_quarantine (
    raw_id  int,
    reason  nvarchar(200)
);

INSERT INTO dbo.debrief_raw (payload) VALUES
(N'{"sortieId":"S-26-0101","tailNo":"TR-101","flownOn":"2026-10-20","flightHrs":1.6,
    "profile":"NAVIGATION",
    "crew":[{"serviceNo":"BD-4471523","role":"PILOT"},{"serviceNo":"BD-4472044","role":"INSTRUCTOR"}],
    "defects":[{"code":"NAV-02","severity":"MINOR","note":"Heading drift after turn"}]}'),
(N'{"sortieId":"S-26-0102","tailNo":"TR-102","flownOn":"2026-10-20","flightHrs":1.1,
    "crew":[{"serviceNo":"BD-4471987","role":"PILOT"}],
    "defects":[]}'),
(N'{"sortieId":"S-26-0103","tailNo":"TR-103","flownOn":"2026-10-21"'),          -- truncated: not JSON
(N'{"sortieId":"S-26-0104","flownOn":"2026-10-21","flightHrs":0.9,"crew":[]}');  -- no tailNo
GO

-- 1) Quarantine bad documents: invalid JSON, or a required field missing.
--    CASE evaluates in order, so JSON_VALUE never runs on text that is not valid JSON.
INSERT INTO dbo.debrief_quarantine (raw_id, reason)
SELECT raw_id, reason
FROM (
    SELECT raw_id,
           CASE WHEN ISJSON(payload) = 0                     THEN N'Invalid JSON'
                WHEN JSON_VALUE(payload, '$.sortieId') IS NULL THEN N'Missing sortieId'
                WHEN JSON_VALUE(payload, '$.tailNo')   IS NULL THEN N'Missing tailNo'
           END AS reason
    FROM dbo.debrief_raw
) q
WHERE reason IS NOT NULL;

-- Stage only the good documents. Parsing from this table means OPENJSON can never touch
-- a bad payload, whatever order the optimizer chooses for joins and filters.
DROP TABLE IF EXISTS #valid;
SELECT r.raw_id, r.payload
INTO #valid
FROM dbo.debrief_raw r
WHERE NOT EXISTS (SELECT 1 FROM dbo.debrief_quarantine q WHERE q.raw_id = r.raw_id);

-- 2) Load good documents into the three tables in one transaction
BEGIN TRANSACTION;

INSERT INTO dbo.debrief_sortie (sortie_id, tail_no, flown_on, flight_hrs, profile)
SELECT j.sortie_id, j.tail_no, j.flown_on, j.flight_hrs, j.profile
FROM #valid r
CROSS APPLY OPENJSON(r.payload) WITH (
    sortie_id  varchar(12)  '$.sortieId',
    tail_no    varchar(10)  '$.tailNo',
    flown_on   date         '$.flownOn',
    flight_hrs decimal(4,2) '$.flightHrs',
    profile    varchar(20)  '$.profile'          -- optional: NULL when absent (lax)
) j

INSERT INTO dbo.debrief_crew (sortie_id, service_no, crew_role)
SELECT h.sortie_id, c.service_no, c.crew_role
FROM #valid r
CROSS APPLY OPENJSON(r.payload) WITH (
    sortie_id varchar(12)   '$.sortieId',
    crew      nvarchar(max) '$.crew' AS JSON
) h
CROSS APPLY OPENJSON(h.crew) WITH (
    service_no varchar(12) '$.serviceNo',
    crew_role  varchar(12) '$.role'
) c

INSERT INTO dbo.debrief_defects (sortie_id, fault_code, severity, note)
SELECT h.sortie_id, d.fault_code, d.severity, d.note
FROM #valid r
CROSS APPLY OPENJSON(r.payload) WITH (
    sortie_id varchar(12)   '$.sortieId',
    defects   nvarchar(max) '$.defects' AS JSON
) h
CROSS APPLY OPENJSON(h.defects) WITH (
    fault_code varchar(10)   '$.code',
    severity   varchar(10)   '$.severity',
    note       nvarchar(200) '$.note'
) d

COMMIT;

SELECT * FROM dbo.debrief_sortie;
SELECT * FROM dbo.debrief_crew;
SELECT * FROM dbo.debrief_defects;
SELECT * FROM dbo.debrief_quarantine;

-- 3) Back to JSON for an API: one document per sortie with nested crew and defect count
SELECT s.sortie_id   AS [sortieId],
       s.tail_no     AS [aircraft.tailNo],
       s.flown_on    AS [aircraft.flownOn],
       s.flight_hrs  AS [aircraft.hours],
       (SELECT c.service_no AS serviceNo, c.crew_role AS role
        FROM dbo.debrief_crew c WHERE c.sortie_id = s.sortie_id
        FOR JSON PATH)                                           AS [crew],
       (SELECT COUNT(*) FROM dbo.debrief_defects d
        WHERE d.sortie_id = s.sortie_id)                         AS [defectCount]
FROM dbo.debrief_sortie s
ORDER BY s.sortie_id
FOR JSON PATH, ROOT('sorties');

-- Expected: 2 sorties loaded (0101 with 2 crew and 1 defect, 0102 with 1 crew),
-- 2 quarantined (raw 3 invalid JSON, raw 4 missing tailNo).
--
-- Why the staging step matters: JSON_VALUE and OPENJSON raise an error on text that is
-- not valid JSON. A WHERE filter in the same query does not guarantee the bad row is
-- removed before parsing, so one broken document could fail the whole load.
-- SQL Server 2022 adds JSON_OBJECT/JSON_ARRAY; Azure SQL also has a native json type.
-- Oracle equivalent: JSON_TABLE with NESTED PATH. PostgreSQL: jsonb_to_recordset.
