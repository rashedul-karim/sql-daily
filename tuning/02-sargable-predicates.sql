-- Topic: Sargable predicates - why a perfectly good index gets ignored
-- Database: PostgreSQL 16
-- Problem: A users table has a B-tree index on email and on created_at, yet three
--          everyday queries do full table scans. Find out why and fix each one,
--          either by rewriting the predicate or by adding an expression index.
-- Note: "Sargable" = Search ARGument ABLE. The optimizer can only use an index when
--       the indexed column appears bare on one side of the comparison. Wrapping the
--       column in a function, doing arithmetic on it, or forcing a type cast on it
--       hides it from the index. Rewrite to move the work to the constant side.

DROP TABLE IF EXISTS app_users;
CREATE TEMP TABLE app_users (
    user_id    bigint PRIMARY KEY,
    email      text,
    created_at timestamptz,
    phone      varchar(20)
);

INSERT INTO app_users
SELECT g,
       'User' || g || '@Example.com',
       now() - (g % 1000) * interval '1 day',
       (8801700000000 + g)::text
FROM generate_series(1, 500000) g;

CREATE INDEX idx_users_email   ON app_users (email);
CREATE INDEX idx_users_created ON app_users (created_at);
CREATE INDEX idx_users_phone   ON app_users (phone);
VACUUM ANALYZE app_users;

-- Case 1: function on the column ---------------------------------------------
-- Bad: Seq Scan, the index on email cannot be used
EXPLAIN ANALYZE
SELECT * FROM app_users WHERE lower(email) = 'user4242@example.com';

-- Fix: index the expression itself
CREATE INDEX idx_users_email_lower ON app_users (lower(email));
ANALYZE app_users;

EXPLAIN ANALYZE
SELECT * FROM app_users WHERE lower(email) = 'user4242@example.com';

-- Case 2: date function on a timestamp column --------------------------------
-- Bad: date_trunc() on the column hides it from idx_users_created
EXPLAIN ANALYZE
SELECT count(*) FROM app_users
WHERE date_trunc('day', created_at) = date_trunc('day', now() - interval '10 days');

-- Fix: rewrite as a half-open range on the bare column
EXPLAIN ANALYZE
SELECT count(*) FROM app_users
WHERE created_at >= date_trunc('day', now() - interval '10 days')
  AND created_at <  date_trunc('day', now() - interval '9 days');

-- Case 3: type mismatch forces a cast on the column --------------------------
-- Bad: phone is varchar but compared to a number, so every row is cast
EXPLAIN ANALYZE
SELECT * FROM app_users WHERE phone::bigint = 8801700004242;

-- Fix: compare with the column's own type
EXPLAIN ANALYZE
SELECT * FROM app_users WHERE phone = '8801700004242';

-- Checklist before blaming the optimizer:
--   1. Is the column bare (no function, no arithmetic, no cast)?
--   2. Does the literal have the same type as the column?
--   3. Are statistics fresh (ANALYZE)?
--   4. Is the predicate selective enough that an index beats a scan?
--
-- Dialects: SQL Server hits the same problem with implicit conversion
-- (CONVERT_IMPLICIT in the plan, common with varchar vs nvarchar parameters) and fixes
-- case 1 with a persisted computed column plus an index. Oracle uses function-based
-- indexes, e.g. CREATE INDEX ... ON app_users (LOWER(email)).
