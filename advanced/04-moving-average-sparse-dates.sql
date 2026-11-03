-- Topic: 7-day moving average when some days have no data
-- Database: PostgreSQL 16
-- Problem: Daily sales are missing for some days. A ROWS-based window would average
--          the last 7 *rows*, which can span 10+ calendar days. Compute a true
--          7-calendar-day moving average and running total, and show the difference.
-- Note: Two correct approaches:
--       (a) RANGE BETWEEN interval '6 days' PRECEDING - frames by value, not row count.
--       (b) Densify with generate_series and LEFT JOIN, so missing days count as zero.
--       They answer different questions: (a) averages days that had sales,
--       (b) treats a missing day as a zero-sales day. Know which one the business wants.

DROP TABLE IF EXISTS sales;
CREATE TEMP TABLE sales (
    sale_date date,
    amount    numeric(10,2)
);

INSERT INTO sales VALUES
    ('2026-02-01', 100), ('2026-02-02', 120), ('2026-02-03',  90),
    -- 4th, 5th, 6th missing
    ('2026-02-07', 200), ('2026-02-08', 210), ('2026-02-09', 180),
    ('2026-02-10', 150), ('2026-02-12', 170);

-- Wrong for this purpose: ROWS counts rows, not days
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (ORDER BY sale_date
             ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS avg_last_7_rows
FROM sales
ORDER BY sale_date;

-- (a) RANGE frame: only rows within the last 7 calendar days
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (ORDER BY sale_date
             RANGE BETWEEN interval '6 days' PRECEDING AND CURRENT ROW), 2) AS avg_7d_range,
       SUM(amount) OVER (ORDER BY sale_date)                                AS running_total
FROM sales
ORDER BY sale_date;

-- (b) Densified calendar: missing days count as zero
WITH calendar AS (
    SELECT d::date AS sale_date
    FROM generate_series(
        (SELECT MIN(sale_date) FROM sales),
        (SELECT MAX(sale_date) FROM sales),
        interval '1 day') AS d
),
dense AS (
    SELECT c.sale_date, COALESCE(s.amount, 0) AS amount
    FROM calendar c
    LEFT JOIN sales s USING (sale_date)
)
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (ORDER BY sale_date
             ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS avg_7d_zero_filled
FROM dense
ORDER BY sale_date;

-- Dialects: SQL Server allows RANGE only with UNBOUNDED or CURRENT ROW, not an offset,
-- so approach (b) is the portable one. Oracle supports RANGE INTERVAL '6' DAY PRECEDING.
