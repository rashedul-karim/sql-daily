-- Topic: Top-N per group - window functions vs LATERAL, and how ties change the answer
-- Database: PostgreSQL 16
-- Problem: For each department, return the top 2 earners. Two people tie on salary
--          in one department. Show how ROW_NUMBER, RANK and DENSE_RANK give different
--          answers, then solve the same problem with LATERAL, which can use an index
--          and stop after N rows per group instead of ranking the whole table.
-- Note: ROW_NUMBER = exactly N rows (ties broken arbitrarily unless you add a tiebreaker).
--       RANK = ties share a rank and leave a gap. DENSE_RANK = ties share a rank, no gap.
--       LATERAL is a correlated subquery in FROM: it runs once per outer row.
--       SQL Server calls it CROSS APPLY; Oracle 12c+ supports both LATERAL and CROSS APPLY.

DROP TABLE IF EXISTS staff;
DROP TABLE IF EXISTS departments;

CREATE TEMP TABLE departments (dept_id int PRIMARY KEY, dept_name text);
CREATE TEMP TABLE staff (
    emp_id  int PRIMARY KEY,
    name    text,
    dept_id int REFERENCES departments,
    salary  int
);

INSERT INTO departments VALUES (1, 'Data'), (2, 'Infra'), (3, 'Security');
INSERT INTO staff VALUES
    (1, 'Arif',   1, 9000), (2, 'Bina',  1, 8500), (3, 'Chanda', 1, 8500),  -- tie
    (4, 'Dipu',   1, 7000),
    (5, 'Esha',   2, 9500), (6, 'Farid', 2, 6000),
    (7, 'Gazi',   3, 8000);                                                 -- only one

-- Compare the three ranking functions side by side
SELECT d.dept_name, s.name, s.salary,
       ROW_NUMBER() OVER w AS row_num,
       RANK()       OVER w AS rnk,
       DENSE_RANK() OVER w AS dense_rnk
FROM staff s
JOIN departments d USING (dept_id)
WINDOW w AS (PARTITION BY s.dept_id ORDER BY s.salary DESC)
ORDER BY d.dept_name, s.salary DESC;

-- Top 2 including ties (Data returns 3 people)
SELECT dept_name, name, salary
FROM (
    SELECT d.dept_name, s.name, s.salary,
           RANK() OVER (PARTITION BY s.dept_id ORDER BY s.salary DESC) AS rnk
    FROM staff s JOIN departments d USING (dept_id)
) t
WHERE rnk <= 2
ORDER BY dept_name, salary DESC;

-- Top 2 per department with LATERAL (exactly 2, deterministic tiebreaker on emp_id)
CREATE INDEX ON staff (dept_id, salary DESC, emp_id);

SELECT d.dept_name, top.name, top.salary
FROM departments d
CROSS JOIN LATERAL (
    SELECT s.name, s.salary
    FROM staff s
    WHERE s.dept_id = d.dept_id
    ORDER BY s.salary DESC, s.emp_id
    LIMIT 2
) top
ORDER BY d.dept_name, top.salary DESC;

-- Use LEFT JOIN LATERAL ... ON true to keep departments that have no staff at all.
