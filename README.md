# sql-daily: Mission-Critical RDBMS Practices & Systems Engineering

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14%20%7C%2015%20%7C%2016-336791?style=flat-square&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Oracle Database](https://img.shields.io/badge/Oracle-19c%20%7C%2023ai-F80000?style=flat-square&logo=oracle&logoColor=white)](https://www.oracle.com/database/)
[![Microsoft SQL Server](https://img.shields.io/badge/SQL%20Server-2016%20%7C%202019%20%7C%202022-CC292B?style=flat-square&logo=microsoftsqlserver&logoColor=white)](https://www.microsoft.com/sql-server)
[![MySQL](https://img.shields.io/badge/MySQL-8.0%20InnoDB-4479A1?style=flat-square&logo=mysql&logoColor=white)](https://www.mysql.com/)

An ongoing, practical showcase of database engineering, query tuning, and RDBMS internals across **Microsoft SQL Server, Oracle Database, PostgreSQL, and MySQL**.

Curated by **Rashed Ul Karim**, database administrator with 20+ years of production experience on Oracle, SQL Server, MySQL and PostgreSQL.

---

### Mandatory Compliance & Data Attribution Notice
> **Notice:** All table schemas, flight identifiers, base locations, telemetry streams, radar tracks, asset tags, serial numbers, and maintenance records across this entire repository are **100% synthetic and fictitious**. They have been compiled independently using mathematical simulations, procedural generators, and open standards for technical portfolio review, systems architecture evaluation, and academic research. No classified, sensitive, proprietary or operational data of any military or government organisation is contained herein.

---

## Repository Architecture

```text
sql-daily/
├── defence/
│   ├── sqlserver/    # 10 Mission-Critical SQL Server Engineering Modules
│   ├── oracle/       # 10 High-Assurance Oracle Database 19c/23ai Modules
│   └── systems/      # 22 Advanced Distributed Systems, Security & Storage Internals
├── advanced/         # Gaps & Islands, Recursive BoM, Sessionization, SCD Type 2
├── tuning/           # Partial/Covering Indexes, Sargability & Expression Indexes
├── joins/            # NOT IN NULL Anti-Join Traps, Lateral Joins & Top-N Optimization
├── dialects/         # Cross-Database Atomic Upsert & Keyset Seek Pagination
└── docker-compose.yml
```

---

## Comprehensive Catalogue

### 1. Defence: Microsoft SQL Server (`defence/sqlserver/`)
* `01-temporal-table-aircraft-configuration.sql`: System-versioned temporal tables for historical fit & change audits (`FOR SYSTEM_TIME`).
* `02-chain-of-command-hierarchyid.sql`: Org structure traversal comparing recursive CTEs against `hierarchyid` seek performance.
* `03-sortie-schedule-conflicts.sql`: Overlapping interval detection and peak airborne fleet calculation.
* `04-pilot-currency-cross-apply.sql`: Rolling 90-day night flying currency checks via correlated `CROSS APPLY`.
* `05-row-level-security-by-unit.sql`: Squadron-level data isolation using `SESSION_CONTEXT` and Security Policies.
* `06-dynamic-data-masking-and-its-limits.sql`: Dynamic Data Masking (DDM) on personnel PII and inference attack vulnerabilities.
* `07-spares-stockout-forecast.sql`: Day-by-day inventory projection, reorder triggers, and stockout date calculation.
* `08-parameter-sniffing-skewed-data.sql`: Diagnosing plan regressions caused by parameter sniffing on skewed base workloads.
* `09-inventory-sync-merge-output-audit.sql`: Safe concurrent depot synchronization using `MERGE ... OUTPUT $action` with `HOLDLOCK`.
* `10-mission-debrief-json-ingestion.sql`: Ingesting complex nested JSON debriefs with `OPENJSON` and quarantine exception routing.

### 2. Defence: Oracle Database (`defence/oracle/`)
* `01-inspection-due-hours-or-calendar.sql`: 100-hour vs 6-month inspection due calculation (`ADD_MONTHS` and `NVL`).
* `02-spares-hierarchy-connect-by.sql`: Bill of Materials tree traversal comparing `CONNECT BY` with recursive `WITH` cycle protection.
* `03-fleet-readiness-from-status-log.sql`: Transforming discrete status changes into intervals with `LEAD` for morning 08:00 readiness reports.
* `04-repeat-defect-match-recognize.sql`: Detecting recurring airframe defects and premature NFF clearances using `MATCH_RECOGNIZE`.
* `05-duty-roster-pivot-unpivot.sql`: Roster grid pivoting with `PIVOT`/`UNPIVOT` and crew rest violation detection.
* `06-need-to-know-access-view.sql`: Multilevel classification enforcement using `SYS_CONTEXT` and `WITH CHECK OPTION`.
* `07-fuel-burn-anomaly-detection.sql`: Fuel burn outlier detection comparing standard Z-score against robust Median / MAD.
* `08-bulk-load-error-logging.sql`: High-speed batch loading isolating bad records via DML `LOG ERRORS` and `FORALL SAVE EXCEPTIONS`.
* `09-telemetry-interval-partitioning.sql`: Monthly auto-partitioning for high-velocity telemetry with local index pruning.
* `10-fefo-stock-allocation.sql`: First-Expired-First-Out shelf-life lot allocation in pure set-based SQL using interval overlap math.

### 3. Defence: Systems, Internals & Distributed Consistency (`defence/systems/`)
* `01-offline-crdt-sync.sql`: State-based Conflict-Free Replicated Data Types (CvRDT) for disconnected base synchronization.
* `02-causal-vector-clocks.sql`: Lamport vector clocks in JSONB tracking tactical causality without synchronized physical clocks.
* `03-spatiotemporal-4d-collision.sql`: 4D trajectory collision detection ($X, Y, Z, t$) with sub-30-second temporal gating.
* `04-vincenty-geodesic-distance.sql`: Vincenty inverse formula on the WGS-84 ellipsoid in a recursive CTE; matches GeographicLib to the millimetre.
* `05-kinematic-kalman-filter.sql`: In-database discrete Kalman filter for radar track smoothing.
* `06-altitude-dependent-zone-check.sql`: Altitude-dependent restricted-zone check with haversine distance in plain SQL.
* `07-hexagonal-binning-track-density.sql`: Hexagonal binning (axial coordinates, cube rounding) to find dense traffic areas.
* `08-boyd-energy-maneuverability.sql`: John Boyd's Specific Excess Power ($P_s$) computed via window functions.
* `09-wal-position-and-xid-age.sql`: First checks after a crash: WAL position, WAL volume per workload, and XID wraparound margin.
* `10-page-corruption-checks-amcheck.sql`: Page and index corruption checks with data checksums and amcheck.
* `11-recoverable-deletes-audit-trigger.sql`: Recoverable deletes: statement-level audit trigger with a transition table, and one-step restore.
* `12-circular-buffer-latest-readings.sql`: Fixed-size circular buffer keeping the latest N readings per sensor with ordered UPSERTs.
* `13-lsm-tree-simulation.sql`: Relational simulation of Log-Structured Merge (LSM) trees with MemTable & SSTable compaction.
* `14-btree-leaf-split-pageinspect.sql`: Diagnosing 50/50 page splits and B-Tree fragmentation using PostgreSQL `pageinspect`.
* `15-merkle-dag-tamperproof-ledger.sql`: Cryptographic Merkle DAG ledger linking flight authorization rows via SHA-256 hashes.
* `16-bell-lapadula-multilevel-security.sql`: Formal Bell-LaPadula Mandatory Access Control (No Read-Up, No Write-Down).
* `17-differential-privacy-laplace.sql`: Bounded Laplacian noise injection on readiness statistics to defeat differencing attacks.
* `18-cell-level-envelope-encryption.sql`: Two-tier envelope encryption with data keys (DEK) wrapped by master keys (KEK).
* `19-why-row-overwrite-is-not-sanitisation.sql`: Shows with pageinspect why overwriting rows does not sanitise data in an MVCC database.
* `20-weibull-failure-mtbf.sql`: Non-parametric Weibull hazard rate estimation for aircraft component MTBF.
* `21-htap-realtime-columnstore.sql`: Real-time HTAP workload isolation running analytics over active write streams.
* `22-cross-engine-table-fingerprint.sql`: Table fingerprints that match across PostgreSQL, Oracle and SQL Server, to detect drift between copies.

### 4. Advanced SQL, Performance Tuning & Dialects (`advanced/`, `tuning/`, `joins/`, `dialects/`)
* `advanced/01-gaps-and-islands-login-streaks.sql`: Gaps & islands consecutive streak analysis using row-number date subtraction.
* `advanced/02-recursive-bom-with-cycle-detection.sql`: Recursive CTE Bill of Materials explosion with path tracking & loop prevention.
* `advanced/03-sessionization-clickstream.sql`: Sessionization by inactivity timeout using `LAG` and running flags.
* `advanced/04-moving-average-sparse-dates.sql`: 7-day moving averages on sparse calendar dates (`RANGE` vs `generate_series`).
* `advanced/05-scd-type2-with-merge.sql`: Idempotent Slowly Changing Dimension (SCD) Type 2 loads using `MERGE`.
* `tuning/01-partial-and-covering-index.sql`: Partial and covering index optimization measured with `EXPLAIN (ANALYZE, BUFFERS)`.
* `tuning/02-sargable-predicates.sql`: Sargable query rewrites and expression-based index optimization.
* `joins/01-not-in-null-trap.sql`: Anti-join pitfalls: why `NOT IN` silently returns empty sets when NULLs exist.
* `joins/02-top-n-per-group-lateral.sql`: Top-N per group comparing window functions against correlated `LATERAL` / `CROSS APPLY`.
* `dialects/01-upsert-and-keyset-pagination.sql`: Keyset seek pagination vs OFFSET, and atomic upsert across PostgreSQL, Oracle, and MSSQL.
