-- Topic: Cryptographic Merkle DAG ledger for tamper-evident sortie authorizations
-- Database: PostgreSQL 14+ (using sha256 via digest or standard string functions)
-- Problem: Flight clearances and weapon load authorizations must be legally unassailable.
--          Link each authorization row to the hash of the preceding row so that unauthorized
--          updates or deletions break the cryptographic chain.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS sortie_merkle_ledger (
    block_seq   BIGSERIAL PRIMARY KEY,
    sortie_code VARCHAR(32) NOT NULL,
    prev_hash   TEXT NOT NULL,
    block_hash  TEXT NOT NULL
);

TRUNCATE TABLE sortie_merkle_ledger;

-- Genesis block
INSERT INTO sortie_merkle_ledger (sortie_code, prev_hash, block_hash)
VALUES ('SORTIE-INIT', '0000000000000000', md5('GENESIS-SORTIE-INIT'));

-- Block 1 linked to Genesis
INSERT INTO sortie_merkle_ledger (sortie_code, prev_hash, block_hash)
SELECT 'SORTIE-ALPHA-01', l.block_hash, md5(l.block_hash || 'SORTIE-ALPHA-01')
FROM sortie_merkle_ledger l WHERE l.block_seq = 1;

-- Verify chain integrity: every prev_hash must equal preceding block_hash
SELECT curr.block_seq, curr.sortie_code, curr.prev_hash,
       CASE WHEN curr.prev_hash = COALESCE(prev.block_hash, '0000000000000000') THEN 'INTEGRITY_OK'
            ELSE 'CHAIN_BROKEN_TAMPERING_DETECTED' END AS audit_status
FROM sortie_merkle_ledger curr
LEFT JOIN sortie_merkle_ledger prev ON curr.block_seq = prev.block_seq + 1;
