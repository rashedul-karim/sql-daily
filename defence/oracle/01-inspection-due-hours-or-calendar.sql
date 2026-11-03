-- Topic: Aircraft inspection due - flying hours or calendar, whichever comes first
-- Database: Oracle 19c+ (also runs on Oracle Database 23ai Free)
-- Problem: Each aircraft must be inspected every 100 flying hours OR every 6 months,
--          whichever comes first. Using the last inspection and the flight log, show
--          hours flown since inspection, the calendar due date, a projected hours due
--          date based on the recent flying rate, and the earlier of the two.
--          Flag aircraft that are overdue or due within 14 days.
-- Note: ADD_MONTHS handles month-end correctly (31 Aug + 6 months = 28/29 Feb).
--       LEAST() picks the earlier date, but returns NULL if any argument is NULL,
--       so wrap the projected date in NVL for aircraft that have not flown recently.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE flight_log PURGE';  EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE inspections PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE inspections (
    tail_no          VARCHAR2(10),
    inspected_on     DATE
);

CREATE TABLE flight_log (
    tail_no      VARCHAR2(10),
    flown_on     DATE,
    hours        NUMBER(5,1)
);

INSERT INTO inspections VALUES ('TR-101', DATE '2026-05-31');
INSERT INTO inspections VALUES ('TR-102', DATE '2026-08-15');
INSERT INTO inspections VALUES ('TR-103', DATE '2026-04-10');

-- TR-101 flies a lot, TR-102 lightly, TR-103 has been grounded (no recent flights)
INSERT INTO flight_log
SELECT 'TR-101', DATE '2026-06-01' + LEVEL * 2, 1.8 FROM dual CONNECT BY LEVEL <= 70;
INSERT INTO flight_log
SELECT 'TR-102', DATE '2026-08-16' + LEVEL * 5, 1.2 FROM dual CONNECT BY LEVEL <= 14;
COMMIT;

WITH as_of AS (
    SELECT DATE '2026-10-24' AS today FROM dual
),
usage AS (
    SELECT i.tail_no,
           i.inspected_on,
           NVL(SUM(f.hours), 0)                                         AS hours_since,
           NVL(SUM(CASE WHEN f.flown_on > a.today - 30 THEN f.hours END), 0) / 30
                                                                        AS hours_per_day
    FROM inspections i
    CROSS JOIN as_of a
    LEFT JOIN flight_log f
           ON f.tail_no = i.tail_no
          AND f.flown_on >  i.inspected_on
          AND f.flown_on <= a.today
    GROUP BY i.tail_no, i.inspected_on
),
due AS (
    SELECT u.*,
           ADD_MONTHS(u.inspected_on, 6)                                AS calendar_due,
           CASE WHEN u.hours_per_day > 0
                THEN a.today + (100 - u.hours_since) / u.hours_per_day
           END                                                          AS hours_due
    FROM usage u CROSS JOIN as_of a
)
SELECT d.tail_no,
       d.inspected_on,
       d.hours_since,
       ROUND(d.hours_per_day, 2)                                        AS hrs_per_day,
       d.calendar_due,
       TRUNC(d.hours_due)                                               AS hours_due,
       TRUNC(LEAST(d.calendar_due, NVL(d.hours_due, d.calendar_due)))   AS next_due,
       CASE
           WHEN d.hours_since >= 100 OR d.calendar_due <= a.today       THEN 'OVERDUE'
           WHEN LEAST(d.calendar_due, NVL(d.hours_due, d.calendar_due))
                <= a.today + 14                                         THEN 'DUE SOON'
           ELSE 'OK'
       END                                                              AS status
FROM due d CROSS JOIN as_of a
ORDER BY next_due;

-- The as_of CTE pins "today" so the result is reproducible. In production use SYSDATE.
-- Expected:
--   TR-101 OVERDUE  (126 hours since 31-MAY, hours limit passed around 21-SEP)
--   TR-103 OVERDUE  (calendar due 10-OCT-2026, no flights to project from)
--   TR-102 OK       (calendar due 15-FEB-2027 comes before the hours limit)
