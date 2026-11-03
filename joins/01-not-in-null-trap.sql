-- Topic: Anti joins - why NOT IN silently returns nothing when NULLs exist
-- Database: PostgreSQL 16 (same behaviour in Oracle and SQL Server)
-- Problem: Find employees who are not managers of anyone. The obvious NOT IN query
--          returns zero rows, with no error. Explain why, then write correct versions.
-- Note: x NOT IN (a, b, NULL) means x <> a AND x <> b AND x <> NULL.
--       x <> NULL is UNKNOWN, so the whole condition is never TRUE.
--       NOT EXISTS and LEFT JOIN ... IS NULL are NULL-safe. NOT EXISTS is usually the
--       clearest, and modern optimizers turn it into an efficient anti join.

DROP TABLE IF EXISTS employees;
CREATE TEMP TABLE employees (
    emp_id     int PRIMARY KEY,
    name       text,
    manager_id int          -- the CEO has no manager: NULL
);

INSERT INTO employees VALUES
    (1, 'CEO',      NULL),
    (2, 'Director', 1),
    (3, 'Manager',  2),
    (4, 'Analyst',  3),
    (5, 'Engineer', 3);

-- Wrong: returns 0 rows because manager_id contains a NULL
SELECT name
FROM employees
WHERE emp_id NOT IN (SELECT manager_id FROM employees);

-- Correct 1: NOT EXISTS
SELECT e.name
FROM employees e
WHERE NOT EXISTS (
    SELECT 1 FROM employees r WHERE r.manager_id = e.emp_id
);

-- Correct 2: LEFT JOIN ... IS NULL
SELECT e.name
FROM employees e
LEFT JOIN employees r ON r.manager_id = e.emp_id
WHERE r.emp_id IS NULL;

-- Correct 3: keep NOT IN but filter NULLs (works, but easy to forget)
SELECT name
FROM employees
WHERE emp_id NOT IN (SELECT manager_id FROM employees WHERE manager_id IS NOT NULL);

-- Compare the plans: NOT EXISTS shows a Hash Anti Join;
-- NOT IN shows a hashed SubPlan filter, which cannot use the anti-join strategy.
EXPLAIN SELECT e.name FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM employees r WHERE r.manager_id = e.emp_id);

EXPLAIN SELECT name FROM employees
WHERE emp_id NOT IN (SELECT manager_id FROM employees);

-- Expected for the correct versions: Analyst, Engineer
