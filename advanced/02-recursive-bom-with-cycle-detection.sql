-- Topic: Recursive CTE - bill of materials explosion with cycle detection
-- Database: PostgreSQL 16
-- Problem: An aircraft part is built from sub-parts, which are built from further
--          sub-parts. Given a top-level part, list every component at every level,
--          the total quantity needed, and the path. Bad data contains a cycle
--          (a part that eventually contains itself), so the query must not loop forever.
-- Note: Multiply quantities down the tree. Track the visited path in an array and stop
--       when a part repeats. PostgreSQL 14+ also has the CYCLE clause, shown at the end.

DROP TABLE IF EXISTS bom;
CREATE TEMP TABLE bom (
    parent_part text,
    child_part  text,
    qty         int
);

INSERT INTO bom VALUES
    ('ENGINE',      'TURBINE',     1),
    ('ENGINE',      'FUEL-PUMP',   2),
    ('TURBINE',     'BLADE',      24),
    ('TURBINE',     'SHAFT',       1),
    ('FUEL-PUMP',   'SEAL-KIT',    3),
    ('SEAL-KIT',    'O-RING',      4),
    ('O-RING',      'SEAL-KIT',    1);   -- bad data: cycle SEAL-KIT -> O-RING -> SEAL-KIT

WITH RECURSIVE explode AS (
    SELECT child_part                    AS part,
           qty                           AS total_qty,
           1                             AS lvl,
           ARRAY['ENGINE', child_part]   AS path,
           false                         AS is_cycle
    FROM bom
    WHERE parent_part = 'ENGINE'

    UNION ALL

    SELECT b.child_part,
           e.total_qty * b.qty,
           e.lvl + 1,
           e.path || b.child_part,
           b.child_part = ANY (e.path)
    FROM explode e
    JOIN bom b ON b.parent_part = e.part
    WHERE NOT e.is_cycle                 -- stop expanding once a cycle is found
)
SELECT repeat('  ', lvl - 1) || part      AS component,
       lvl,
       total_qty,
       array_to_string(path, ' > ')       AS path,
       is_cycle
FROM explode
ORDER BY path;

-- Same result with the built-in CYCLE clause (PostgreSQL 14+):
WITH RECURSIVE explode AS (
    SELECT child_part AS part, qty AS total_qty, 1 AS lvl
    FROM bom WHERE parent_part = 'ENGINE'
    UNION ALL
    SELECT b.child_part, e.total_qty * b.qty, e.lvl + 1
    FROM explode e JOIN bom b ON b.parent_part = e.part
) CYCLE part SET is_cycle USING path
SELECT part, lvl, total_qty, is_cycle
FROM explode
ORDER BY path;

-- Oracle equivalent: CONNECT BY NOCYCLE PRIOR child_part = parent_part, with CONNECT_BY_ISCYCLE.
-- SQL Server: recursive CTE as above, with OPTION (MAXRECURSION n) as a safety limit.
