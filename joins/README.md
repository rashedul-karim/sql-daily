# Relational Joins & Anti-Join Patterns

Optimization of multi-table joins, lateral subqueries, and anti-join trap avoidance.

## File Index
1. `01-not-in-null-trap.sql`: Anti-join trap: why `NOT IN` silently returns nothing when NULLs exist.
2. `02-top-n-per-group-lateral.sql`: Top-N per group comparing window functions against correlated `LATERAL` / `CROSS APPLY`.
