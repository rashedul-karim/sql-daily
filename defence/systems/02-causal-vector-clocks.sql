-- Topic: Lamport causal vector clocks via JSONB for multi-radar correlation
-- Database: PostgreSQL 14+
-- Problem: Physical wall clocks across distributed radar shelters experience clock drift.
--          Ordering tactical events by timestamp can invert cause and effect (scramble order
--          appearing before target detection). Implement vector clocks in JSONB to evaluate
--          causal dominance V(a) < V(b) without trusting physical time.
-- All data is fictional.

CREATE SCHEMA IF NOT EXISTS causal_engine;
SET search_path TO causal_engine, public;

DROP TABLE IF EXISTS tactical_events CASCADE;
CREATE TABLE tactical_events (
    event_id        BIGSERIAL PRIMARY KEY,
    origin_node     VARCHAR(32) NOT NULL,
    clock_vector    JSONB       NOT NULL,
    event_payload   TEXT        NOT NULL
);

CREATE OR REPLACE FUNCTION is_causally_prior(a JSONB, b JSONB) RETURNS BOOLEAN AS $$
DECLARE
    k TEXT;
    has_strictly_less BOOLEAN := FALSE;
    va INT; vb INT;
BEGIN
    FOR k IN SELECT DISTINCT jsonb_object_keys(a) UNION SELECT jsonb_object_keys(b)
    LOOP
        va := COALESCE((a->>k)::INT, 0);
        vb := COALESCE((b->>k)::INT, 0);
        IF va > vb THEN RETURN FALSE; END IF;
        IF va < vb THEN has_strictly_less := TRUE; END IF;
    END LOOP;
    RETURN has_strictly_less;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

INSERT INTO tactical_events (origin_node, clock_vector, event_payload) VALUES
('RADAR_SECTOR_1', '{"R1": 1, "HQ": 0}'::jsonb, 'Unidentified contact bearing 045 range 60NM'),
('AIR_HQ',         '{"R1": 1, "HQ": 1}'::jsonb, 'Scramble interceptor tail TR-102');

SELECT e1.event_payload AS cause, e2.event_payload AS effect,
       is_causally_prior(e1.clock_vector, e2.clock_vector) AS causality_verified
FROM tactical_events e1, tactical_events e2
WHERE e1.event_id = 1 AND e2.event_id = 2;
