-- Topic: State-based Conflict-Free Replicated Data Types (CvRDT) in pure SQL
-- Database: PostgreSQL 14+
-- Problem: Forward airbases frequently lose wide-area network links due to jamming or terrain.
--          Traditional 2PC or master-slave replication fails or aborts when disconnected bases
--          must continue issuing and receiving mission-critical aircraft spares locally.
--          Implement a state-based P-N counter and LWW element set in pure SQL using a
--          join-semilattice (GREATEST) that converges deterministically with zero merge conflicts.
-- All data is fictional.

CREATE SCHEMA IF NOT EXISTS crdt_sync;
SET search_path TO crdt_sync, public;

DROP TABLE IF EXISTS inventory_counter_state CASCADE;

CREATE TABLE inventory_counter_state (
    item_id         VARCHAR(64)  NOT NULL,
    base_id         VARCHAR(32)  NOT NULL,
    items_added     BIGINT       NOT NULL DEFAULT 0,
    items_used      BIGINT       NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT pk_inv_counter PRIMARY KEY (item_id, base_id)
);

-- Merge incoming state vector: uses supremum (GREATEST) to preserve monotonicity
CREATE OR REPLACE FUNCTION merge_remote_stock(
    p_item_id VARCHAR(64), p_base_id VARCHAR(32), p_remote_added BIGINT, p_remote_used BIGINT, p_remote_time TIMESTAMPTZ
) RETURNS VOID AS $$
BEGIN
    INSERT INTO inventory_counter_state (item_id, base_id, items_added, items_used, updated_at)
    VALUES (p_item_id, p_base_id, p_remote_added, p_remote_used, p_remote_time)
    ON CONFLICT (item_id, base_id)
    DO UPDATE SET
        items_added = GREATEST(inventory_counter_state.items_added, EXCLUDED.items_added),
        items_used  = GREATEST(inventory_counter_state.items_used, EXCLUDED.items_used),
        updated_at  = GREATEST(inventory_counter_state.updated_at, EXCLUDED.updated_at);
END;
$$ LANGUAGE plpgsql;

-- Initial central baseline
INSERT INTO inventory_counter_state VALUES ('RADAR-TUBE-V4', 'BASE_MAIN', 100, 10, clock_timestamp());

-- Disconnected remote updates: Base Bravo uses 15, Base Charlie receives 30
SELECT merge_remote_stock('RADAR-TUBE-V4', 'BASE_BRAVO', 0, 15, clock_timestamp());
SELECT merge_remote_stock('RADAR-TUBE-V4', 'BASE_CHARLIE', 30, 0, clock_timestamp());

-- Replay Base Bravo update (testing idempotency under duplicate packet transmission)
SELECT merge_remote_stock('RADAR-TUBE-V4', 'BASE_BRAVO', 0, 15, clock_timestamp());

-- Query total converged inventory
SELECT item_id, SUM(items_added) AS total_in, SUM(items_used) AS total_out,
       SUM(items_added) - SUM(items_used) AS net_available
FROM inventory_counter_state GROUP BY item_id;
-- Expected: 130 in, 25 out, net 105.
