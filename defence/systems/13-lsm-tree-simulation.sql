-- Topic: Log-Structured Merge (LSM) Tree storage simulation in relational SQL
-- Database: PostgreSQL 14+
-- Problem: B-Trees suffer from write amplification on flash memory, wearing out SSDs in deployable
--          field server enclosures. Implement an LSM storage architecture with an in-memory
--          MemTable and sequential append-only SSTable tiers merged via background compaction.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS lsm_memtable (
    key_id    VARCHAR(32) PRIMARY KEY,
    val_data  TEXT,
    inserted_at TIMESTAMPTZ DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS lsm_sstable_tier1 (
    key_id    VARCHAR(32),
    val_data  TEXT,
    flushed_at TIMESTAMPTZ DEFAULT clock_timestamp()
);

INSERT INTO lsm_memtable VALUES ('TR-101', 'STATUS_READY'), ('TR-102', 'STATUS_MAINT');

-- Flush MemTable to immutable SSTable tier sequentially
INSERT INTO lsm_sstable_tier1 (key_id, val_data)
SELECT key_id, val_data FROM lsm_memtable ORDER BY key_id;
TRUNCATE TABLE lsm_memtable;

SELECT * FROM lsm_sstable_tier1 ORDER BY key_id;
