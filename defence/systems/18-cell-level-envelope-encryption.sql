-- Topic: Application-blind cell-level envelope encryption patterns in SQL
-- Database: PostgreSQL (pgcrypto) / Oracle
-- Problem: If physical database backup tapes or disk volumes are captured, critical telemetry
--          must remain undecryptable without hardware keys. Encrypt sensitive columns using
--          Data Encryption Keys (DEKs) wrapped by master Key Encryption Keys (KEKs).
-- All data is fictional.

CREATE TABLE IF NOT EXISTS encrypted_sortie_orders (
    sortie_id   INT PRIMARY KEY,
    target_zone TEXT NOT NULL -- Holds base64 encrypted payload
);

-- Simulation of cell encryption: stores encrypted ciphertext token
INSERT INTO encrypted_sortie_orders VALUES
(101, 'ENC(AES256,DEK_KEY_01,COORDINATES_WAYPOINT_NORTH)')
ON CONFLICT (sortie_id) DO NOTHING;

SELECT sortie_id, target_zone AS raw_stored_ciphertext
FROM encrypted_sortie_orders;
