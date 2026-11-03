-- Topic: Sortie schedule conflicts - overlapping intervals and minimum turnaround
-- Database: SQL Server 2016+
-- Problem: The flying programme assigns a pilot and an aircraft to each sortie slot.
--          Before it is published, find every clash:
--          (1) a pilot booked on two sorties that overlap in time,
--          (2) an aircraft booked again before its 45-minute turnaround is complete,
--          (3) the peak number of aircraft airborne at the same time (to check
--              against the number of crews and air traffic capacity).
-- Note: Two intervals [s1, e1) and [s2, e2) overlap exactly when s1 < e2 AND s2 < e1.
--       Self-join on that, with a.id < b.id so each pair appears once.
--       For "how many at the same time", turn each sortie into +1 at start and -1 at
--       end, sort the events, and keep a running sum: the maximum is the peak.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.sortie_plan;
GO

CREATE TABLE dbo.sortie_plan (
    sortie_id  int          PRIMARY KEY,
    pilot      varchar(10)  NOT NULL,
    tail_no    varchar(10)  NOT NULL,
    take_off   datetime2(0) NOT NULL,
    land       datetime2(0) NOT NULL,
    CHECK (land > take_off)
);

INSERT INTO dbo.sortie_plan VALUES
    (1, 'P-ALAM',  'TR-101', '2026-10-26 08:00', '2026-10-26 09:30'),
    (2, 'P-BASHIR','TR-102', '2026-10-26 08:15', '2026-10-26 09:15'),
    (3, 'P-ALAM',  'TR-103', '2026-10-26 09:00', '2026-10-26 10:00'),  -- pilot clash with 1
    (4, 'P-CHOWDHURY','TR-101', '2026-10-26 10:00', '2026-10-26 11:00'),  -- 30 min turnaround
    (5, 'P-BASHIR','TR-102', '2026-10-26 10:00', '2026-10-26 11:00'),  -- 45 min: OK
    (6, 'P-DEWAN', 'TR-104', '2026-10-26 08:30', '2026-10-26 09:45'),
    (7, 'P-ALAM',  'TR-104', '2026-10-26 10:00', '2026-10-26 11:00');  -- touches 3 at 10:00: OK

-- 1) Pilot double-booked (overlap test)
SELECT a.pilot,
       a.sortie_id AS sortie_1, b.sortie_id AS sortie_2,
       CASE WHEN a.take_off > b.take_off THEN a.take_off ELSE b.take_off END AS clash_from,
       CASE WHEN a.land     < b.land     THEN a.land     ELSE b.land     END AS clash_to
FROM dbo.sortie_plan a
JOIN dbo.sortie_plan b
  ON a.pilot = b.pilot
 AND a.sortie_id < b.sortie_id
 AND a.take_off < b.land
 AND b.take_off < a.land;

-- 2) Aircraft turnaround shorter than 45 minutes (compare each sortie with the next one)
WITH seq AS (
    SELECT tail_no, sortie_id, take_off, land,
           LEAD(sortie_id) OVER (PARTITION BY tail_no ORDER BY take_off) AS next_sortie,
           LEAD(take_off)  OVER (PARTITION BY tail_no ORDER BY take_off) AS next_take_off
    FROM dbo.sortie_plan
)
SELECT tail_no, sortie_id, land, next_sortie, next_take_off,
       DATEDIFF(MINUTE, land, next_take_off) AS turnaround_min
FROM seq
WHERE next_take_off IS NOT NULL
  AND DATEDIFF(MINUTE, land, next_take_off) < 45;

-- 3) Peak aircraft airborne at once
WITH events AS (
    SELECT take_off AS t, +1 AS delta FROM dbo.sortie_plan
    UNION ALL
    SELECT land,          -1          FROM dbo.sortie_plan
),
running AS (
    SELECT t, delta,
           SUM(delta) OVER (ORDER BY t, delta
                            ROWS UNBOUNDED PRECEDING) AS airborne
    FROM events
)
SELECT TOP (1) WITH TIES t AS peak_time, airborne AS peak_airborne
FROM running
ORDER BY airborne DESC;

-- Expected:
--   1) P-ALAM: sorties 1 and 3 clash 09:00-09:30. Sorties 3 and 7 touch at 10:00, not a clash.
--   2) TR-101: lands 09:30, next take-off 10:00 = 30 minutes.
--      TR-104: lands 09:45, next take-off 10:00 = 15 minutes. TR-102 has exactly 45: OK.
--   3) Peak 4 airborne at 09:00.
--
-- Why ORDER BY t, delta: at the same instant, landings (-1) are counted before
-- take-offs (+1), so a hand-over at 10:00 is not double counted.
-- PostgreSQL can enforce the pilot rule in the table itself with an exclusion constraint:
--   EXCLUDE USING gist (pilot WITH =, tsrange(take_off, land) WITH &&)
