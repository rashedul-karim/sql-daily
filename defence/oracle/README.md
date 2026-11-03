# Defence: Oracle Database 19c / 23ai Modules

Advanced Oracle database scripts focusing on operational availability, partitioning, analytics, and data security.

## File Index
1. `01-inspection-due-hours-or-calendar.sql`: Inspection due date calculations (hours vs calendar with `ADD_MONTHS`).
2. `02-spares-hierarchy-connect-by.sql`: Spare parts breakdown tree using `CONNECT BY` and recursive `WITH`.
3. `03-fleet-readiness-from-status-log.sql`: Daily fleet readiness rate generated from status-change logs using `LEAD`.
4. `04-repeat-defect-match-recognize.sql`: Detecting recurring airframe defects using `MATCH_RECOGNIZE`.
5. `05-duty-roster-pivot-unpivot.sql`: Duty roster grid transformation with `PIVOT`/`UNPIVOT` and rest rule validation.
6. `06-need-to-know-access-view.sql`: Security classification access control with `SYS_CONTEXT` and `WITH CHECK OPTION`.
7. `07-fuel-burn-anomaly-detection.sql`: Sortie fuel burn outlier detection: Z-score vs robust Median/MAD.
8. `08-bulk-load-error-logging.sql`: High-speed bulk loading with `LOG ERRORS` and `FORALL SAVE EXCEPTIONS`.
9. `09-telemetry-interval-partitioning.sql`: Monthly auto-partitioning for high-velocity telemetry with local index pruning.
10. `10-fefo-stock-allocation.sql`: First-Expired-First-Out (FEFO) stock allocation in pure SQL via interval overlap math.
