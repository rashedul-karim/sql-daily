# Advanced SQL Patterns & Relational Analytics

Complex relational modeling, event sessionization, and recursive hierarchy traversal.

## File Index
1. `01-gaps-and-islands-login-streaks.sql`: Gaps & islands consecutive day streak analysis.
2. `02-recursive-bom-with-cycle-detection.sql`: Recursive CTE Bill of Materials explosion with path cycle detection.
3. `03-sessionization-clickstream.sql`: Sessionization by inactivity timeout with `LAG` and running flags.
4. `04-moving-average-sparse-dates.sql`: 7-day moving averages on sparse calendar dates (`RANGE` vs densification).
5. `05-scd-type2-with-merge.sql`: Idempotent Slowly Changing Dimension (SCD) Type 2 loads using `MERGE`.
