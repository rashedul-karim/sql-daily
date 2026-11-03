-- Topic: Pilot currency check - rolling 90-day window with CROSS APPLY
-- Database: SQL Server 2016+
-- Problem: To fly a night sortie, a pilot must have logged at least 3 night landings in
--          the 90 days before the sortie date (landing date > sortie date - 90).
--          For each planned night sortie, show the pilot's qualifying landings and whether they are current. For pilots who are
--          not current, show the date their currency lapsed. For pilots who are current,
--          show the date it will lapse if they log no more night landings.
-- Note: SQL Server's RANGE frame cannot take an interval ("90 days preceding"), so a
--       window function cannot do a calendar-based rolling count. CROSS APPLY runs a
--       correlated subquery per planned sortie and can use an index on
--       (pilot, landed_on). OUTER APPLY keeps rows when the subquery returns nothing.
--       Lapse date = date of the 3rd most recent qualifying landing + 90 days, which is
--       the first day the pilot is no longer current.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.landings;
DROP TABLE IF EXISTS dbo.night_plan;
GO

CREATE TABLE dbo.landings (
    pilot      varchar(10) NOT NULL,
    landed_on  date        NOT NULL,
    is_night   bit         NOT NULL,
    count_ldg  tinyint     NOT NULL DEFAULT 1
);
CREATE INDEX ix_landings ON dbo.landings (pilot, is_night, landed_on) INCLUDE (count_ldg);

CREATE TABLE dbo.night_plan (
    sortie_id  int PRIMARY KEY,
    pilot      varchar(10) NOT NULL,
    sortie_on  date        NOT NULL
);

INSERT INTO dbo.landings (pilot, landed_on, is_night, count_ldg) VALUES
    ('P-ALAM',   '2026-08-10', 1, 1),
    ('P-ALAM',   '2026-09-02', 1, 2),    -- two night landings in one sortie
    ('P-ALAM',   '2026-10-05', 0, 3),    -- day landings do not count
    ('P-BASHIR', '2026-08-03', 1, 1),
    ('P-BASHIR', '2026-08-05', 1, 1),
    ('P-BASHIR', '2026-08-08', 1, 1),    -- current until 31-Oct, lapses 01-Nov
    ('P-DEWAN',  '2026-10-01', 1, 1);    -- only 1

INSERT INTO dbo.night_plan VALUES
    (101, 'P-ALAM',   '2026-10-28'),
    (102, 'P-BASHIR', '2026-10-28'),
    (103, 'P-BASHIR', '2026-11-05'),
    (104, 'P-DEWAN',  '2026-10-28'),
    (105, 'P-EHSAN',  '2026-10-28');     -- no landings at all

-- Expand landings so each landing is one row (needed to find "the 3rd most recent")
WITH each_landing AS (
    SELECT l.pilot, l.landed_on
    FROM dbo.landings l
    CROSS APPLY (SELECT TOP (l.count_ldg) 1 AS n
                 FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9)) v(x)) x
    WHERE l.is_night = 1
)
SELECT p.sortie_id, p.pilot, p.sortie_on,
       ISNULL(w.night_landings, 0)                     AS night_ldg_last_90d,
       CASE WHEN ISNULL(w.night_landings, 0) >= 3
            THEN 'CURRENT' ELSE 'NOT CURRENT' END      AS status,
       DATEADD(DAY, 90, third.landed_on)               AS currency_lapses_on
FROM dbo.night_plan p
OUTER APPLY (
    SELECT COUNT(*) AS night_landings
    FROM each_landing e
    WHERE e.pilot = p.pilot
      AND e.landed_on >  DATEADD(DAY, -90, p.sortie_on)
      AND e.landed_on <  p.sortie_on
) w
OUTER APPLY (
    SELECT e.landed_on
    FROM each_landing e
    WHERE e.pilot = p.pilot
      AND e.landed_on < p.sortie_on
    ORDER BY e.landed_on DESC
    OFFSET 2 ROWS FETCH NEXT 1 ROW ONLY          -- the 3rd most recent landing
) third
ORDER BY p.sortie_id;

-- Expected:
--   101 P-ALAM    3  CURRENT      lapses 08-Nov-2026 (3rd most recent = 10-Aug)
--   102 P-BASHIR  3  CURRENT      lapses 01-Nov-2026: only 4 days of margin, flag for planners
--   103 P-BASHIR  1  NOT CURRENT  lapsed 01-Nov-2026 (only 08-Aug is inside the window)
--   104 P-DEWAN   1  NOT CURRENT  no lapse date: never had 3
--   105 P-EHSAN   0  NOT CURRENT
--
-- The same rolling check in Oracle or PostgreSQL can use a window frame instead:
--   SUM(count_ldg) OVER (PARTITION BY pilot ORDER BY landed_on
--                        RANGE BETWEEN INTERVAL '90' DAY PRECEDING AND CURRENT ROW)
