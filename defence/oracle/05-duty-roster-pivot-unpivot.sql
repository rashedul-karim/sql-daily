-- Topic: Duty roster with PIVOT and UNPIVOT - plus fairness and rest-rule checks
-- Database: Oracle 11g+
-- Problem: The duty roster is stored one row per person per day. The orderly room wants
--          the familiar grid view (one row per person, one column per weekday).
--          The planning team sends back a grid spreadsheet that must be loaded as rows.
--          Finally, check two rules: nobody does more than 2 night duties a week, and
--          nobody does a night duty followed directly by a day duty (rest violation).
-- Note: PIVOT needs a fixed column list. UNPIVOT turns columns back into rows and drops
--       NULLs unless you say INCLUDE NULLS. Rule checks use LAG over each person's days.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE duty_roster PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE roster_grid_import PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE duty_roster (
    service_no  VARCHAR2(10),
    duty_date   DATE,
    shift       VARCHAR2(5)       -- DAY, NIGHT, OFF
);

INSERT INTO duty_roster
SELECT p.service_no, DATE '2026-10-25' + d.n,
       CASE MOD(p.seed + d.n, 4) WHEN 0 THEN 'NIGHT' WHEN 1 THEN 'OFF' ELSE 'DAY' END
FROM (SELECT 'S1001' service_no, 0 seed FROM dual UNION ALL
      SELECT 'S1002', 1 FROM dual UNION ALL
      SELECT 'S1003', 2 FROM dual) p
CROSS JOIN (SELECT LEVEL - 1 n FROM dual CONNECT BY LEVEL <= 7) d;

-- Force a rest violation and an extra night for S1003
UPDATE duty_roster SET shift = 'NIGHT'
WHERE service_no = 'S1003' AND duty_date IN (DATE '2026-10-25', DATE '2026-10-29');
COMMIT;

-- 1) PIVOT: grid view, one column per day of the week (25-OCT-2026 is a Sunday)
SELECT *
FROM (
    SELECT service_no, TO_CHAR(duty_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') AS dow, shift
    FROM duty_roster
)
PIVOT (MAX(shift) FOR dow IN ('SUN' AS sun, 'MON' AS mon, 'TUE' AS tue, 'WED' AS wed,
                              'THU' AS thu, 'FRI' AS fri, 'SAT' AS sat))
ORDER BY service_no;

-- 2) UNPIVOT: load a grid that came back from planners, blanks included
CREATE TABLE roster_grid_import (
    service_no VARCHAR2(10),
    sun VARCHAR2(5), mon VARCHAR2(5), tue VARCHAR2(5), wed VARCHAR2(5),
    thu VARCHAR2(5), fri VARCHAR2(5), sat VARCHAR2(5)
);
INSERT INTO roster_grid_import VALUES ('S2001', 'DAY', 'DAY', NULL, 'NIGHT', 'OFF', 'DAY', 'DAY');
COMMIT;

SELECT service_no,
       DATE '2026-11-01' + day_offset   AS duty_date,
       NVL(shift, 'UNASSIGNED')         AS shift
FROM roster_grid_import
UNPIVOT INCLUDE NULLS (shift FOR day_offset IN (
    sun AS 0, mon AS 1, tue AS 2, wed AS 3, thu AS 4, fri AS 5, sat AS 6))
ORDER BY duty_date;

-- 3) Rule checks
WITH seq AS (
    SELECT service_no, duty_date, shift,
           LAG(shift) OVER (PARTITION BY service_no ORDER BY duty_date) AS prev_shift,
           COUNT(CASE WHEN shift = 'NIGHT' THEN 1 END)
                 OVER (PARTITION BY service_no)                         AS nights_in_week
    FROM duty_roster
)
SELECT service_no, duty_date, prev_shift || ' -> ' || shift AS change,
       'Night followed by day duty' AS violation
FROM seq
WHERE prev_shift = 'NIGHT' AND shift = 'DAY'
UNION ALL
SELECT DISTINCT service_no, NULL, TO_CHAR(nights_in_week) || ' nights',
       'More than 2 nights in the week'
FROM seq
WHERE nights_in_week > 2
ORDER BY 1, 2;

-- Expected violations (all S1003):
--   26-OCT NIGHT -> DAY, 30-OCT NIGHT -> DAY, and 4 nights in the week.

-- Dynamic PIVOT (unknown column list) needs dynamic SQL or PIVOT XML in Oracle.
-- SQL Server has PIVOT/UNPIVOT with almost the same syntax, without INCLUDE NULLS:
-- use CROSS APPLY (VALUES ...) instead when blanks must be kept.
