-- Topic: Spare parts hierarchy with CONNECT BY - quantities, leaf parts and cycles
-- Database: Oracle 19c+
-- Problem: An engine assembly breaks down into modules, sub-assemblies and consumable
--          parts. For an engine overhaul, list the full tree with indentation, the total
--          quantity of each part (multiplied down the tree), mark leaf parts (the ones
--          actually ordered from stores), and survive a data-entry cycle.
-- Note: CONNECT BY is great for display (LEVEL, paths, leaf and cycle flags) but has no
--       clean way to multiply quantities down the tree. Recursive WITH (11gR2+) carries
--       a running product, and its SEARCH and CYCLE clauses give ordering and loop safety.
--       NOCYCLE + CONNECT_BY_ISCYCLE stops the loop and tells you where it was.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE part_structure PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE part_structure (
    parent_part VARCHAR2(20),
    child_part  VARCHAR2(20),
    qty         NUMBER
);

INSERT INTO part_structure VALUES (NULL,           'ENGINE-ASSY',  1);
INSERT INTO part_structure VALUES ('ENGINE-ASSY',  'COMPRESSOR',   1);
INSERT INTO part_structure VALUES ('ENGINE-ASSY',  'FUEL-CTRL',    1);
INSERT INTO part_structure VALUES ('COMPRESSOR',   'STAGE-DISK',   5);
INSERT INTO part_structure VALUES ('STAGE-DISK',   'BLADE',       30);
INSERT INTO part_structure VALUES ('STAGE-DISK',   'LOCK-WIRE',    2);
INSERT INTO part_structure VALUES ('FUEL-CTRL',    'FILTER',       2);
INSERT INTO part_structure VALUES ('FILTER',       'GASKET',       2);
INSERT INTO part_structure VALUES ('GASKET',       'FILTER',       1);  -- bad data: cycle
COMMIT;

-- 1) CONNECT BY: tree, path, leaf flag, cycle flag
SELECT LPAD(' ', 2 * (LEVEL - 1)) || child_part        AS part_tree,
       LEVEL                                           AS lvl,
       qty,
       SYS_CONNECT_BY_PATH(child_part, ' > ')          AS path,
       CONNECT_BY_ISLEAF                               AS is_leaf,
       CONNECT_BY_ISCYCLE                              AS is_cycle
FROM part_structure
START WITH parent_part IS NULL
CONNECT BY NOCYCLE PRIOR child_part = parent_part
ORDER SIBLINGS BY child_part;

-- 2) Recursive WITH: total quantity multiplied down the tree, with cycle detection
WITH tree (part, total_qty, lvl, path) AS (
    SELECT child_part, qty, 1, CAST(child_part AS VARCHAR2(400))
    FROM part_structure
    WHERE parent_part IS NULL
    UNION ALL
    SELECT p.child_part, t.total_qty * p.qty, t.lvl + 1,
           t.path || ' > ' || p.child_part
    FROM tree t
    JOIN part_structure p ON p.parent_part = t.part
)
SEARCH DEPTH FIRST BY part SET sort_order
CYCLE part SET is_cycle TO 'Y' DEFAULT 'N'
SELECT LPAD(' ', 2 * (lvl - 1)) || part AS part_tree,
       total_qty,
       is_cycle
FROM tree
ORDER BY sort_order;

-- 3) Stores order list: leaf parts only, quantities summed across the tree
WITH tree (part, total_qty) AS (
    SELECT child_part, qty FROM part_structure WHERE parent_part IS NULL
    UNION ALL
    SELECT p.child_part, t.total_qty * p.qty
    FROM tree t JOIN part_structure p ON p.parent_part = t.part
)
CYCLE part SET is_cycle TO 'Y' DEFAULT 'N'
SELECT part, SUM(total_qty) AS order_qty
FROM tree t
WHERE is_cycle = 'N'
  AND NOT EXISTS (SELECT 1 FROM part_structure p WHERE p.parent_part = t.part)
GROUP BY part
ORDER BY part;

-- Expected order list: BLADE 150, LOCK-WIRE 10.
-- GASKET and FILTER are not leaves because of the cycle: the query exposes the bad data
-- instead of hiding it. Fix the source row, rerun, and GASKET 4 appears.
