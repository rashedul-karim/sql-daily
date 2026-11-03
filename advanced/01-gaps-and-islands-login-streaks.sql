-- Topic: Gaps and islands - longest consecutive login streak per user
-- Database: PostgreSQL 16
-- Problem: Users log in many times a day, some days not at all. For each user,
--          find their longest run of consecutive login days, with start and end dates.
-- Note: Subtracting ROW_NUMBER() (as days) from the date gives the same "anchor" value
--       for every day in an unbroken run. Group by that anchor and each group is one streak.
--       Deduplicate to one row per user per day first, or multiple logins break the trick.

DROP TABLE IF EXISTS logins;
CREATE TEMP TABLE logins (
    user_id   int,
    login_at  timestamptz
);

INSERT INTO logins VALUES
    (1, '2026-01-01 08:00'), (1, '2026-01-01 21:00'),   -- two logins same day
    (1, '2026-01-02 09:00'), (1, '2026-01-03 10:00'),
    (1, '2026-01-05 10:00'),                            -- gap on 4th
    (1, '2026-01-06 10:00'), (1, '2026-01-07 10:00'), (1, '2026-01-08 10:00'),
    (2, '2026-01-01 07:00'), (2, '2026-01-03 07:00'),
    (2, '2026-01-04 07:00');

WITH daily AS (                      -- one row per user per day
    SELECT DISTINCT user_id, login_at::date AS d
    FROM logins
),
grouped AS (
    SELECT user_id, d,
           d - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY d))::int AS anchor
    FROM daily
),
streaks AS (
    SELECT user_id,
           MIN(d)   AS streak_start,
           MAX(d)   AS streak_end,
           COUNT(*) AS days
    FROM grouped
    GROUP BY user_id, anchor
)
SELECT DISTINCT ON (user_id)
       user_id, streak_start, streak_end, days
FROM streaks
ORDER BY user_id, days DESC, streak_start;   -- longest; earliest wins a tie

-- Expected:
--  user_id | streak_start | streak_end | days
--        1 | 2026-01-05   | 2026-01-08 |    4
--        2 | 2026-01-03   | 2026-01-04 |    2
