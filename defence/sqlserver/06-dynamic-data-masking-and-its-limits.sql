-- Topic: Dynamic Data Masking on personnel data - and why it is not encryption
-- Database: SQL Server 2016+ (granular column UNMASK needs SQL Server 2022 / Azure SQL)
-- Problem: A personnel table holds service numbers, mobile numbers, emails and dates of
--          birth. Helpdesk staff need to find a person but must not see full personal
--          details; the personnel office needs everything. Apply masking, grant UNMASK to
--          the right role, and then show how a masked user can still infer a value,
--          so the team understands what masking does and does not protect against.
-- Note: Masking changes only what a query RETURNS. The real value is still used in
--       WHERE, JOIN and ORDER BY. A user who can run ad-hoc queries can guess a masked
--       value one comparison at a time. Use masking to reduce casual exposure in apps and
--       reports; use permissions, Always Encrypted or column encryption for real secrecy.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.personnel;
IF USER_ID('helpdesk_user')   IS NOT NULL DROP USER helpdesk_user;
IF USER_ID('personnel_offr')  IS NOT NULL DROP USER personnel_offr;
GO

CREATE TABLE dbo.personnel (
    person_id   int          PRIMARY KEY,
    service_no  varchar(12)  MASKED WITH (FUNCTION = 'partial(0,"XXXX",3)') NOT NULL,
    full_name   varchar(60)  NOT NULL,
    mobile      varchar(15)  MASKED WITH (FUNCTION = 'partial(4,"*******",2)') NULL,
    email       varchar(60)  MASKED WITH (FUNCTION = 'email()') NULL,
    dob         date         MASKED WITH (FUNCTION = 'default()') NULL,
    years_svc   tinyint      MASKED WITH (FUNCTION = 'random(1, 40)') NULL
);

INSERT INTO dbo.personnel VALUES
    (1, 'BD-4471523', 'Karim Hossain',  '+8801711000111', 'k.hossain@example.mil', '1988-04-12', 16),
    (2, 'BD-4471987', 'Nusrat Jahan',   '+8801811000222', 'n.jahan@example.mil',   '1992-11-03', 11),
    (3, 'BD-4472044', 'Tanvir Ahmed',   '+8801911000333', 't.ahmed@example.mil',   '1985-01-27', 19);

CREATE USER helpdesk_user  WITHOUT LOGIN;
CREATE USER personnel_offr WITHOUT LOGIN;
GRANT SELECT ON dbo.personnel TO helpdesk_user, personnel_offr;
GRANT UNMASK TO personnel_offr;     -- SQL Server 2022: GRANT UNMASK ON dbo.personnel(mobile) TO ...
GO

-- 1) Helpdesk view: masked
EXECUTE AS USER = 'helpdesk_user';
SELECT person_id, service_no, full_name, mobile, email, dob, years_svc FROM dbo.personnel;
REVERT;

-- 2) Personnel officer view: real values
EXECUTE AS USER = 'personnel_offr';
SELECT person_id, service_no, full_name, mobile, email, dob, years_svc FROM dbo.personnel;
REVERT;
GO

-- 3) The limit: helpdesk user infers a masked date of birth with WHERE clauses.
--    Binary search over dates needs only about 15 queries to pin down an exact day.
EXECUTE AS USER = 'helpdesk_user';

DECLARE @lo date = '1950-01-01', @hi date = '2010-12-31', @mid date, @hits int, @queries int = 0;
WHILE @lo < @hi
BEGIN
    SET @mid = DATEADD(DAY, DATEDIFF(DAY, @lo, @hi) / 2, @lo);
    SELECT @hits = COUNT(*) FROM dbo.personnel WHERE person_id = 2 AND dob <= @mid;
    SET @queries += 1;
    IF @hits = 1
        SET @hi = @mid;
    ELSE
        SET @lo = DATEADD(DAY, 1, @mid);
END;
SELECT @lo AS inferred_dob, @queries AS queries_needed;

REVERT;
GO

-- Expected:
--   1) Helpdesk sees XXXX523, +880*******11, kXXX@XXXX.com, 1900-01-01, and random years.
--   2) Personnel officer sees the full values.
--   3) inferred_dob = 1992-11-03 after about 15 queries: masking did not hide it.
--
-- Mitigations:
--   - Do not give masked users ad-hoc query access; expose stored procedures or views.
--   - Audit unusual query patterns (SQL Server Audit, Extended Events).
--   - For data that must stay secret even from DBAs: Always Encrypted.
-- Oracle equivalent: Data Redaction (DBMS_REDACT), which has the same inference caveat.
