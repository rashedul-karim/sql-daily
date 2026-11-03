-- Topic: Chain of command - recursive CTE vs hierarchyid
-- Database: SQL Server 2016+
-- Problem: An organisation chart: wing, squadrons, flights, sections. Answer three
--          questions fast: (1) everyone under a given commander at any depth,
--          (2) the full reporting chain above a given person, (3) span of control
--          (direct reports and total headcount) per post.
--          Then move a whole section to another flight in one operation.
-- Note: A parent_id column with a recursive CTE is simple to maintain but re-walks the
--       tree for every query. hierarchyid stores each node's path in a compact binary
--       value, so "all descendants" becomes a range seek on an index (IsDescendantOf),
--       and moving a subtree is GetReparentedValue. Trade-off: you maintain the path.
-- All data is fictional.

SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.org_posts;
GO

CREATE TABLE dbo.org_posts (
    post_id    int          PRIMARY KEY,
    parent_id  int          NULL REFERENCES dbo.org_posts (post_id),
    post_title varchar(40)  NOT NULL,
    node       hierarchyid  NULL
);

INSERT INTO dbo.org_posts (post_id, parent_id, post_title) VALUES
    ( 1, NULL, 'Wing Commander (OC Wing)'),
    ( 2, 1,    'OC Squadron A'),
    ( 3, 1,    'OC Squadron B'),
    ( 4, 2,    'Flight Commander A1'),
    ( 5, 2,    'Flight Commander A2'),
    ( 6, 3,    'Flight Commander B1'),
    ( 7, 4,    'Section Leader A1-1'),
    ( 8, 4,    'Section Leader A1-2'),
    ( 9, 7,    'Technician A1-1-a'),
    (10, 7,    'Technician A1-1-b'),
    (11, 6,    'Section Leader B1-1'),
    (12, 11,   'Technician B1-1-a');
GO

-- 1) Recursive CTE: everyone under OC Squadron A, with depth and path
WITH chain AS (
    SELECT post_id, post_title, 0 AS depth,
           CAST(post_title AS varchar(400)) AS path
    FROM dbo.org_posts WHERE post_id = 2
    UNION ALL
    SELECT p.post_id, p.post_title, c.depth + 1,
           CAST(c.path + ' > ' + p.post_title AS varchar(400))
    FROM chain c
    JOIN dbo.org_posts p ON p.parent_id = c.post_id
)
SELECT REPLICATE('    ', depth) + post_title AS org_tree, depth
FROM chain
ORDER BY path
OPTION (MAXRECURSION 50);   -- safety stop if bad data ever creates a loop

-- 2) Build the hierarchyid column from parent_id (one-off backfill)
WITH build AS (
    SELECT post_id, hierarchyid::GetRoot() AS node
    FROM dbo.org_posts WHERE parent_id IS NULL
    UNION ALL
    SELECT p.post_id,
           CAST(b.node.ToString()
                + CAST(ROW_NUMBER() OVER (PARTITION BY p.parent_id ORDER BY p.post_id) AS varchar(10))
                + '/' AS hierarchyid)
    FROM build b
    JOIN dbo.org_posts p ON p.parent_id = b.post_id
)
UPDATE o SET node = b.node
FROM dbo.org_posts o JOIN build b ON b.post_id = o.post_id;

CREATE UNIQUE INDEX ix_org_node ON dbo.org_posts (node);   -- depth-first index
GO

-- 3) All descendants of OC Squadron A: a single index range seek, no recursion
DECLARE @sqnA hierarchyid = (SELECT node FROM dbo.org_posts WHERE post_id = 2);

SELECT REPLICATE('    ', node.GetLevel() - @sqnA.GetLevel()) + post_title AS org_tree,
       node.ToString() AS path
FROM dbo.org_posts
WHERE node.IsDescendantOf(@sqnA) = 1
ORDER BY node;

-- 4) Reporting chain above a technician (ancestors)
DECLARE @tech hierarchyid = (SELECT node FROM dbo.org_posts WHERE post_id = 9);

SELECT node.GetLevel() AS lvl, post_title
FROM dbo.org_posts
WHERE @tech.IsDescendantOf(node) = 1
ORDER BY node.GetLevel();

-- 5) Span of control: direct reports and total people below each post
SELECT m.post_title,
       (SELECT COUNT(*) FROM dbo.org_posts d WHERE d.node.GetAncestor(1) = m.node) AS direct_reports,
       (SELECT COUNT(*) FROM dbo.org_posts d WHERE d.node.IsDescendantOf(m.node) = 1) - 1 AS total_below
FROM dbo.org_posts m
ORDER BY m.node;
GO

-- 6) Reorganisation: move Section A1-1 (with its technicians) under Flight Commander B1
DECLARE @newParent hierarchyid = (SELECT node FROM dbo.org_posts WHERE post_id = 6);
DECLARE @section   hierarchyid = (SELECT node FROM dbo.org_posts WHERE post_id = 7);

-- New position: after the last existing child of the new parent
DECLARE @lastChild hierarchyid =
    (SELECT MAX(node) FROM dbo.org_posts WHERE node.GetAncestor(1) = @newParent);
DECLARE @newSection hierarchyid = @newParent.GetDescendant(@lastChild, NULL);

UPDATE dbo.org_posts
SET node      = node.GetReparentedValue(@section, @newSection),
    parent_id = CASE WHEN post_id = 7 THEN 6 ELSE parent_id END   -- keep both models in sync
WHERE node.IsDescendantOf(@section) = 1;

SELECT REPLICATE('    ', node.GetLevel()) + post_title AS org_tree, node.ToString() AS path
FROM dbo.org_posts
ORDER BY node;

-- Expected after the move: Section Leader A1-1 and both A1-1 technicians now sit under
-- Flight Commander B1, after Section Leader B1-1.
-- Oracle equivalent of section 1: CONNECT BY. PostgreSQL equivalent of hierarchyid: ltree.
