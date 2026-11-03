-- Topic: Sessionization - split a clickstream into sessions by inactivity
-- Database: PostgreSQL 16
-- Problem: Web events have only a user and a timestamp. A new session starts when a
--          user is inactive for more than 30 minutes. Assign a session number to every
--          event, then report each session's start, end, duration and event count.
-- Note: LAG() finds the previous event. Flag 1 when the gap exceeds the timeout (or there
--       is no previous event), then a running SUM of the flag numbers the sessions.
--       This is the same pattern Spark and dbt sessionization models use.

DROP TABLE IF EXISTS events;
CREATE TEMP TABLE events (
    user_id  int,
    event_at timestamp,
    page     text
);

INSERT INTO events VALUES
    (1, '2026-03-01 09:00', 'home'),
    (1, '2026-03-01 09:05', 'search'),
    (1, '2026-03-01 09:20', 'product'),
    (1, '2026-03-01 10:30', 'home'),       -- 70 min gap: new session
    (1, '2026-03-01 10:31', 'cart'),
    (2, '2026-03-01 09:00', 'home'),
    (2, '2026-03-01 09:29', 'search'),     -- 29 min: same session
    (2, '2026-03-01 10:00', 'checkout');   -- 31 min: new session

WITH flagged AS (
    SELECT *,
           CASE
               WHEN LAG(event_at) OVER w IS NULL
                 OR event_at - LAG(event_at) OVER w > interval '30 minutes'
               THEN 1 ELSE 0
           END AS new_session
    FROM events
    WINDOW w AS (PARTITION BY user_id ORDER BY event_at)
),
numbered AS (
    SELECT *,
           SUM(new_session) OVER (PARTITION BY user_id ORDER BY event_at) AS session_no
    FROM flagged
)
SELECT user_id,
       session_no,
       MIN(event_at)                    AS session_start,
       MAX(event_at)                    AS session_end,
       MAX(event_at) - MIN(event_at)    AS duration,
       COUNT(*)                         AS events,
       string_agg(page, ' > ' ORDER BY event_at) AS journey
FROM numbered
GROUP BY user_id, session_no
ORDER BY user_id, session_no;

-- Expected: user 1 has 2 sessions, user 2 has 2 sessions.
