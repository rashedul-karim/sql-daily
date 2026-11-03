# Defence: Microsoft SQL Server Modules

Practical, production-grade SQL Server scripts designed for high-assurance aviation and defense logistics environments.

## File Index
1. `01-temporal-table-aircraft-configuration.sql`: System-versioned temporal tables for historical fit audits.
2. `02-chain-of-command-hierarchyid.sql`: Chain of command org charts: recursive CTEs vs `hierarchyid` seek performance.
3. `03-sortie-schedule-conflicts.sql`: Overlapping interval detection and peak airborne fleet analysis.
4. `04-pilot-currency-cross-apply.sql`: Rolling 90-day night sortie currency check with `CROSS APPLY`.
5. `05-row-level-security-by-unit.sql`: Row-Level Security by squadron unit with `SESSION_CONTEXT`.
6. `06-dynamic-data-masking-and-its-limits.sql`: Dynamic Data Masking on personnel data and inference limit analysis.
7. `07-spares-stockout-forecast.sql`: Spares stockout forecast with projected daily balances and lead times.
8. `08-parameter-sniffing-skewed-data.sql`: Parameter sniffing diagnosis, statistics I/O measurement, and mitigation.
9. `09-inventory-sync-merge-output-audit.sql`: Depot inventory sync using `MERGE` with `OUTPUT $action` audit and `HOLDLOCK`.
10. `10-mission-debrief-json-ingestion.sql`: Ingesting nested debrief JSON records with `OPENJSON` and quarantine routing.
