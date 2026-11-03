-- Topic: Daily fleet readiness rate from a status-change log
-- Database: Oracle 19c+
-- Problem: The maintenance system records only status changes:
--          aircraft X became 'SERVICEABLE' or 'UNSERVICEABLE' at a time.
--          Commanders want a daily report: how many aircraft were serviceable at
--          08:00 each morning, and the readiness percentage, for a date range.
--          Also show each aircraft's total unserviceable hours in the period.
-- Note: Turn change events into intervals with LEAD (each status lasts until the next
--       change). Generate a calendar with CONNECT BY LEVEL, then join each 08:00 check
--       time to the interval that contains it. This "events to intervals to snapshots"
--       pattern is the core of most status and availability reporting.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE status_log PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE status_log (
    tail_no    VARCHAR2(10),
    changed_at DATE,
    status     VARCHAR2(15)
);

INSERT INTO status_log VALUES ('TR-101', TIMESTAMP '2026-10-01 00:00:00', 'SERVICEABLE');
INSERT INTO status_log VALUES ('TR-101', TIMESTAMP '2026-10-03 14:00:00', 'UNSERVICEABLE');
INSERT INTO status_log VALUES ('TR-101', TIMESTAMP '2026-10-05 09:30:00', 'SERVICEABLE');
INSERT INTO status_log VALUES ('TR-102', TIMESTAMP '2026-10-01 00:00:00', 'UNSERVICEABLE');
INSERT INTO status_log VALUES ('TR-102', TIMESTAMP '2026-10-02 07:00:00', 'SERVICEABLE');
INSERT INTO status_log VALUES ('TR-103', TIMESTAMP '2026-10-01 00:00:00', 'SERVICEABLE');
INSERT INTO status_log VALUES ('TR-103', TIMESTAMP '2026-10-06 08:15:00', 'UNSERVICEABLE');
INSERT INTO status_log VALUES ('TR-104', TIMESTAMP '2026-10-01 00:00:00', 'SERVICEABLE');
COMMIT;

-- 1) Daily readiness at 08:00
WITH params AS (
    SELECT DATE '2026-10-01' AS from_date, DATE '2026-10-07' AS to_date FROM dual
),
intervals AS (
    SELECT tail_no, status,
           changed_at                                                    AS valid_from,
           LEAD(changed_at, 1, DATE '9999-12-31')
                OVER (PARTITION BY tail_no ORDER BY changed_at)          AS valid_to
    FROM status_log
),
checks AS (
    SELECT p.from_date + LEVEL - 1 + 8/24 AS check_time
    FROM params p
    CONNECT BY LEVEL <= p.to_date - p.from_date + 1
)
SELECT TRUNC(c.check_time)                                               AS report_day,
       COUNT(*)                                                          AS fleet,
       SUM(CASE WHEN i.status = 'SERVICEABLE' THEN 1 ELSE 0 END)         AS serviceable,
       ROUND(100 * AVG(CASE WHEN i.status = 'SERVICEABLE' THEN 1 ELSE 0 END), 1)
                                                                         AS readiness_pct,
       LISTAGG(CASE WHEN i.status = 'UNSERVICEABLE' THEN i.tail_no END, ', ')
           WITHIN GROUP (ORDER BY i.tail_no)                             AS down_aircraft
FROM checks c
JOIN intervals i
  ON c.check_time >= i.valid_from
 AND c.check_time <  i.valid_to
GROUP BY TRUNC(c.check_time)
ORDER BY report_day;

-- 2) Unserviceable hours per aircraft, clipped to the report window
WITH params AS (
    SELECT DATE '2026-10-01' AS from_date, DATE '2026-10-07' AS to_date FROM dual
),
intervals AS (
    SELECT tail_no, status,
           changed_at AS valid_from,
           LEAD(changed_at, 1, DATE '9999-12-31')
                OVER (PARTITION BY tail_no ORDER BY changed_at) AS valid_to
    FROM status_log
)
SELECT i.tail_no,
       ROUND(SUM(LEAST(i.valid_to, p.to_date + 1) - GREATEST(i.valid_from, p.from_date)) * 24, 1)
                                                                AS hours_down
FROM intervals i CROSS JOIN params p
WHERE i.status = 'UNSERVICEABLE'
  AND i.valid_from < p.to_date + 1
  AND i.valid_to   > p.from_date
GROUP BY i.tail_no
ORDER BY hours_down DESC;

-- Expected readiness: 01-OCT 75%, 02-OCT 100%, 03-OCT 100% (TR-101 fails at 14:00),
-- 04-OCT 75%, 05-OCT 75% (TR-101 fixed at 09:30, after the check), 06-OCT 100%
-- (TR-103 fails at 08:15, just after), 07-OCT 75%.
-- Expected hours down: TR-101 43.5, TR-103 39.8 (clipped at window end), TR-102 31.
