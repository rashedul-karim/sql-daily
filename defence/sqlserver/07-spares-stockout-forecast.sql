-- Topic: Spares stock-out forecast - running balance, reorder trigger, first breach date
-- Database: SQL Server 2016+
-- Problem: Stores know today's stock of each spare, the planned issues (scheduled
--          maintenance demand) and the expected receipts (orders already placed).
--          For each item, project the day-by-day balance for the next 60 days, find the
--          first date it falls below the reorder level, the first date it hits zero
--          (stock-out), and whether an order placed today would arrive in time given
--          the item's lead time.
-- Note: Combine opening stock, issues (negative) and receipts (positive) into one movement
--       stream, then SUM() OVER (ORDER BY date) gives the projected balance.
--       "First date the condition is true" = MIN(date) WHERE condition, per item.
--       ROWS UNBOUNDED PRECEDING avoids the slower default RANGE frame in SQL Server.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.spares;
DROP TABLE IF EXISTS dbo.planned_moves;
GO

CREATE TABLE dbo.spares (
    item_code      varchar(12) PRIMARY KEY,
    on_hand        int NOT NULL,
    reorder_level  int NOT NULL,
    lead_time_days int NOT NULL
);

CREATE TABLE dbo.planned_moves (
    item_code  varchar(12) NOT NULL,
    move_date  date        NOT NULL,
    qty        int         NOT NULL,     -- negative = issue, positive = receipt
    move_type  varchar(10) NOT NULL
);

INSERT INTO dbo.spares VALUES
    ('BRK-PAD-07', 40, 15, 21),
    ('FLT-HYD-02', 12,  5, 45),
    ('TYR-MAIN-1', 18,  6, 10);

INSERT INTO dbo.planned_moves VALUES
    ('BRK-PAD-07', '2026-10-30', -10, 'ISSUE'),
    ('BRK-PAD-07', '2026-11-06', -12, 'ISSUE'),
    ('BRK-PAD-07', '2026-11-15', -10, 'ISSUE'),
    ('BRK-PAD-07', '2026-11-20',  20, 'RECEIPT'),
    ('BRK-PAD-07', '2026-11-28', -30, 'ISSUE'),
    ('FLT-HYD-02', '2026-11-02',  -4, 'ISSUE'),
    ('FLT-HYD-02', '2026-11-16',  -4, 'ISSUE'),
    ('FLT-HYD-02', '2026-12-01',  -4, 'ISSUE'),
    ('TYR-MAIN-1', '2026-11-10',  -4, 'ISSUE'),
    ('TYR-MAIN-1', '2026-12-10',  -4, 'ISSUE');

DECLARE @today date = '2026-10-24', @horizon int = 60;

WITH moves AS (
    SELECT item_code, @today AS move_date, on_hand AS qty, 'OPENING' AS move_type
    FROM dbo.spares
    UNION ALL
    SELECT item_code, move_date, qty, move_type
    FROM dbo.planned_moves
    WHERE move_date >  @today
      AND move_date <= DATEADD(DAY, @horizon, @today)
),
projection AS (
    SELECT m.item_code, m.move_date, m.move_type, m.qty,
           SUM(m.qty) OVER (PARTITION BY m.item_code
                            ORDER BY m.move_date, CASE m.move_type WHEN 'OPENING' THEN 0 ELSE 1 END
                            ROWS UNBOUNDED PRECEDING) AS balance,
           s.reorder_level, s.lead_time_days
    FROM moves m
    JOIN dbo.spares s ON s.item_code = m.item_code
)
-- 1) Projected balance after every movement
SELECT item_code, move_date, move_type, qty, balance,
       CASE WHEN balance <= 0             THEN 'STOCK-OUT'
            WHEN balance < reorder_level  THEN 'BELOW REORDER'
       END AS flag
FROM projection
ORDER BY item_code, move_date;

-- 2) One line per item: when it breaches, and whether ordering today is fast enough
WITH moves AS (
    SELECT item_code, @today AS move_date, on_hand AS qty
    FROM dbo.spares
    UNION ALL
    SELECT item_code, move_date, qty
    FROM dbo.planned_moves
    WHERE move_date > @today AND move_date <= DATEADD(DAY, @horizon, @today)
),
projection AS (
    SELECT item_code, move_date,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY move_date
                          ROWS UNBOUNDED PRECEDING) AS balance
    FROM moves
)
SELECT s.item_code,
       MIN(CASE WHEN p.balance < s.reorder_level THEN p.move_date END) AS first_below_reorder,
       MIN(CASE WHEN p.balance <= 0              THEN p.move_date END) AS first_stock_out,
       DATEADD(DAY, s.lead_time_days, @today)                          AS order_today_arrives,
       CASE
           WHEN MIN(CASE WHEN p.balance <= 0 THEN p.move_date END) IS NULL THEN 'OK in horizon'
           WHEN DATEADD(DAY, s.lead_time_days, @today)
                <= MIN(CASE WHEN p.balance <= 0 THEN p.move_date END)       THEN 'ORDER NOW'
           ELSE 'TOO LATE - expedite or borrow'
       END AS action
FROM dbo.spares s
JOIN projection p ON p.item_code = s.item_code
GROUP BY s.item_code, s.reorder_level, s.lead_time_days
ORDER BY first_stock_out;

-- Expected (as of 24-Oct-2026):
--   BRK-PAD-07: below reorder 15-Nov (8), receipt lifts it to 28, then stock-out 28-Nov (-2).
--               Lead time 21 days, order today arrives 14-Nov: ORDER NOW.
--   FLT-HYD-02: below reorder 16-Nov (4), stock-out 01-Dec (0).
--               Lead time 45 days, order today arrives 08-Dec: TOO LATE.
--   TYR-MAIN-1: lowest balance 10, above its reorder level of 6, inside the horizon: OK.
--   TYR-MAIN-1 is listed first because SQL Server sorts NULL first in ascending order.
