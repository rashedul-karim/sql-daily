-- Topic: Repeat-defect detection with MATCH_RECOGNIZE
-- Database: Oracle 12c+
-- Problem: A defect is a "repeat defect" when the same fault code is raised on the same
--          aircraft 3 or more times within 30 days, which means the earlier fixes did not
--          work. Find every such chain with first and last report dates and the count.
--          Then find a second pattern: a fault cleared "no fault found" (NFF) that comes
--          back within 7 days, a classic sign of an intermittent problem.
-- Note: MATCH_RECOGNIZE runs a regular expression over ordered rows.
--       PARTITION BY = per aircraft and fault, ORDER BY = time, PATTERN = the sequence,
--       DEFINE = conditions per row. FIRST() refers to the first row of the current match.
--       Doing this with self-joins or window functions is possible but far harder to read.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE defect_reports PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE defect_reports (
    report_id   NUMBER PRIMARY KEY,
    tail_no     VARCHAR2(10),
    fault_code  VARCHAR2(10),
    reported_on DATE,
    action      VARCHAR2(20)        -- REPLACED, ADJUSTED, NFF (no fault found)
);

INSERT INTO defect_reports VALUES ( 1, 'TR-101', 'HYD-07', DATE '2026-09-01', 'ADJUSTED');
INSERT INTO defect_reports VALUES ( 2, 'TR-101', 'HYD-07', DATE '2026-09-12', 'REPLACED');
INSERT INTO defect_reports VALUES ( 3, 'TR-101', 'HYD-07', DATE '2026-09-25', 'REPLACED');  -- 3rd in 30 days
INSERT INTO defect_reports VALUES ( 4, 'TR-101', 'HYD-07', DATE '2026-09-28', 'REPLACED');  -- 4th
INSERT INTO defect_reports VALUES ( 5, 'TR-102', 'NAV-02', DATE '2026-09-01', 'NFF');
INSERT INTO defect_reports VALUES ( 6, 'TR-102', 'NAV-02', DATE '2026-09-05', 'NFF');       -- back in 4 days
INSERT INTO defect_reports VALUES ( 7, 'TR-102', 'NAV-02', DATE '2026-09-20', 'REPLACED');
INSERT INTO defect_reports VALUES ( 8, 'TR-103', 'ELE-11', DATE '2026-08-01', 'REPLACED');
INSERT INTO defect_reports VALUES ( 9, 'TR-103', 'ELE-11', DATE '2026-08-20', 'REPLACED');
INSERT INTO defect_reports VALUES (10, 'TR-103', 'ELE-11', DATE '2026-09-15', 'REPLACED');  -- 45 days span: not a repeat
COMMIT;

-- 1) Repeat defects: 3+ reports of the same fault within 30 days of the first one
SELECT tail_no, fault_code, first_report, last_report, reports, first_id, last_id
FROM defect_reports
MATCH_RECOGNIZE (
    PARTITION BY tail_no, fault_code
    ORDER BY reported_on
    MEASURES FIRST(reported_on)                  AS first_report,
             LAST(reported_on)                   AS last_report,
             COUNT(*)                            AS reports,
             FIRST(report_id)                    AS first_id,
             LAST(report_id)                     AS last_id
    ONE ROW PER MATCH
    AFTER MATCH SKIP PAST LAST ROW
    PATTERN (strt nxt{2,})
    DEFINE nxt AS reported_on <= FIRST(strt.reported_on) + 30
);

-- 2) NFF followed by the same fault within 7 days
SELECT tail_no, fault_code, nff_date, returned_on, days_later
FROM defect_reports
MATCH_RECOGNIZE (
    PARTITION BY tail_no, fault_code
    ORDER BY reported_on
    MEASURES nff.reported_on                      AS nff_date,
             back.reported_on                     AS returned_on,
             back.reported_on - nff.reported_on   AS days_later
    ONE ROW PER MATCH
    AFTER MATCH SKIP TO NEXT ROW
    PATTERN (nff back)
    DEFINE nff  AS action = 'NFF',
           back AS reported_on <= PREV(reported_on) + 7
);

-- Expected:
--   1) TR-101 HYD-07, 01-SEP to 28-SEP, 4 reports (ids 1 to 4).
--      TR-102 NAV-02, 01-SEP to 20-SEP, 3 reports (ids 5 to 7).
--      TR-103 is not listed: its 3 reports span 45 days.
--   2) TR-102 NAV-02, NFF on 01-SEP, back on 05-SEP, 4 days later.
--
-- Dialects: SQL Server and PostgreSQL have no MATCH_RECOGNIZE. The usual substitute is
-- LAG/LEAD or a self-join on (fault_code, date window), which gets messy past 2 steps.
-- Snowflake and Trino support MATCH_RECOGNIZE.
