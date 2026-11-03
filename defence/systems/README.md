# Defence: Distributed Systems, Storage Internals & Forensics

Database internals, replication and consistency patterns, spatial calculations and recovery checks, each as a runnable script.

## File Index
* `01-offline-crdt-sync.sql`: State-based Conflict-Free Replicated Data Types (CvRDT) in pure SQL.
* `02-causal-vector-clocks.sql`: Lamport vector clocks in JSONB tracking tactical causality.
* `03-spatiotemporal-4d-collision.sql`: 4D trajectory collision detection ($X, Y, Z, t$) with temporal gating.
* `04-vincenty-geodesic-distance.sql`: Vincenty inverse formula on the WGS-84 ellipsoid in a recursive CTE; matches GeographicLib to the millimetre.
* `05-kinematic-kalman-filter.sql`: Recursive discrete Kalman filter for radar track smoothing.
* `06-altitude-dependent-zone-check.sql`: Altitude-dependent restricted-zone check with haversine distance in plain SQL.
* `07-hexagonal-binning-track-density.sql`: Hexagonal binning (axial coordinates, cube rounding) to find dense traffic areas.
* `08-boyd-energy-maneuverability.sql`: Boyd's Energy-Maneuverability formulation ($P_s$) in window functions.
* `09-wal-position-and-xid-age.sql`: First checks after a crash: WAL position, WAL volume per workload, and XID wraparound margin.
* `10-page-corruption-checks-amcheck.sql`: Page and index corruption checks with data checksums and amcheck.
* `11-recoverable-deletes-audit-trigger.sql`: Recoverable deletes: statement-level audit trigger with a transition table, and one-step restore.
* `12-circular-buffer-latest-readings.sql`: Fixed-size circular buffer keeping the latest N readings per sensor with ordered UPSERTs.
* `13-lsm-tree-simulation.sql`: Relational simulation of Log-Structured Merge (LSM) trees with MemTable & SSTable compaction.
* `14-btree-leaf-split-pageinspect.sql`: B-Tree leaf page split and index fragmentation analysis with `pageinspect`.
* `15-merkle-dag-tamperproof-ledger.sql`: Cryptographic Merkle DAG ledger for flight authorizations.
* `16-bell-lapadula-multilevel-security.sql`: Formal Bell-LaPadula Mandatory Access Control (No Read-Up, No Write-Down).
* `17-differential-privacy-laplace.sql`: Differential privacy query engine adding bounded Laplace noise.
* `18-cell-level-envelope-encryption.sql`: Application-blind cell-level envelope encryption patterns.
* `19-why-row-overwrite-is-not-sanitisation.sql`: Shows with pageinspect why overwriting rows does not sanitise data in an MVCC database.
* `20-weibull-failure-mtbf.sql`: Non-parametric Weibull hazard rate & Mean Time Between Failures (MTBF).
* `21-htap-realtime-columnstore.sql`: Real-Time HTAP workload isolation with Clustered Columnstore.
* `22-cross-engine-table-fingerprint.sql`: Table fingerprints that match across PostgreSQL, Oracle and SQL Server, to detect drift between copies.
