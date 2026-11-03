-- Topic: First-Expired-First-Out (FEFO) stock allocation in one SQL statement
-- Database: Oracle 19c+
-- Problem: Shelf-life items (sealants, lubricants, O-ring kits) are held in several lots
--          with different expiry dates. Expired lots must never be issued. Given a set of
--          demands, allocate stock from the lots that expire first, splitting a demand
--          across lots when needed, and show what is left and any shortfall.
-- Note: This is an interval-overlap problem. Cumulative SUM over lots (ordered by expiry)
--       gives each lot a range [from, to) of units. Cumulative SUM over demands gives each
--       demand a range too. A demand takes from every lot whose range overlaps its range,
--       and the quantity is the size of the overlap:
--           LEAST(lot_to, dem_to) - GREATEST(lot_from, dem_from)
--       No loops, no cursors, and it scales to thousands of lots.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE stock_lots PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE demands PURGE';    EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE stock_lots (
    lot_no     VARCHAR2(10),
    item_code  VARCHAR2(10),
    expiry     DATE,
    qty        NUMBER
);

CREATE TABLE demands (
    demand_id  NUMBER,
    item_code  VARCHAR2(10),
    needed_by  DATE,
    qty        NUMBER
);

INSERT INTO stock_lots VALUES ('L-01', 'SEAL-A', DATE '2026-09-30', 50);   -- already expired
INSERT INTO stock_lots VALUES ('L-02', 'SEAL-A', DATE '2026-11-30', 40);
INSERT INTO stock_lots VALUES ('L-03', 'SEAL-A', DATE '2027-03-31', 60);
INSERT INTO stock_lots VALUES ('L-04', 'SEAL-A', DATE '2027-08-31', 30);
INSERT INTO stock_lots VALUES ('L-10', 'OIL-B',  DATE '2027-01-31', 20);

INSERT INTO demands VALUES (1, 'SEAL-A', DATE '2026-10-26', 25);
INSERT INTO demands VALUES (2, 'SEAL-A', DATE '2026-10-27', 45);
INSERT INTO demands VALUES (3, 'SEAL-A', DATE '2026-10-28', 70);
INSERT INTO demands VALUES (4, 'OIL-B',  DATE '2026-10-26', 35);   -- more than stock
COMMIT;

WITH params AS (
    SELECT DATE '2026-10-24' AS today FROM dual
),
lots AS (
    SELECT l.*,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY expiry, lot_no) - qty AS lot_from,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY expiry, lot_no)       AS lot_to
    FROM stock_lots l CROSS JOIN params p
    WHERE l.expiry > p.today                         -- never issue expired stock
),
dem AS (
    SELECT d.*,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY needed_by, demand_id) - qty AS dem_from,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY needed_by, demand_id)       AS dem_to
    FROM demands d
)
SELECT d.demand_id, d.item_code, d.qty AS demanded,
       l.lot_no, l.expiry,
       LEAST(l.lot_to, d.dem_to) - GREATEST(l.lot_from, d.dem_from) AS issued
FROM dem d
JOIN lots l
  ON l.item_code = d.item_code
 AND l.lot_from  < d.dem_to
 AND l.lot_to    > d.dem_from
ORDER BY d.demand_id, l.expiry;

-- Shortfall per demand and remaining stock per lot
WITH params AS (SELECT DATE '2026-10-24' AS today FROM dual),
lots AS (
    SELECT l.*,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY expiry, lot_no) - qty AS lot_from,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY expiry, lot_no)       AS lot_to
    FROM stock_lots l CROSS JOIN params p
    WHERE l.expiry > p.today
),
dem AS (
    SELECT d.*,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY needed_by, demand_id) - qty AS dem_from,
           SUM(qty) OVER (PARTITION BY item_code ORDER BY needed_by, demand_id)       AS dem_to
    FROM demands d
),
alloc AS (
    SELECT d.demand_id, l.lot_no,
           LEAST(l.lot_to, d.dem_to) - GREATEST(l.lot_from, d.dem_from) AS issued
    FROM dem d
    JOIN lots l ON l.item_code = d.item_code
               AND l.lot_from < d.dem_to AND l.lot_to > d.dem_from
)
SELECT 'DEMAND ' || d.demand_id                AS line,
       d.qty - NVL(SUM(a.issued), 0)           AS shortfall_or_remaining
FROM demands d LEFT JOIN alloc a ON a.demand_id = d.demand_id
GROUP BY d.demand_id, d.qty
HAVING d.qty - NVL(SUM(a.issued), 0) > 0
UNION ALL
SELECT 'LOT ' || l.lot_no, l.qty - NVL(SUM(a.issued), 0)
FROM lots l LEFT JOIN alloc a ON a.lot_no = l.lot_no
GROUP BY l.lot_no, l.qty
ORDER BY 1;

-- Expected allocation (lot L-01 is expired and skipped):
--   demand 1: 25 from L-02
--   demand 2: 15 from L-02, 30 from L-03
--   demand 3: 30 from L-03, 30 from L-04, then 10 short
--   demand 4: 20 from L-10, then 15 short
-- Remaining: L-02 0, L-03 0, L-04 0, L-10 0.
