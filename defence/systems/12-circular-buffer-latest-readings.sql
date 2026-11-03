-- Topic: Fixed-size circular buffer for latest sensor readings
-- Database: PostgreSQL 14+
-- Problem: A dashboard only needs the last N readings per sensor. Keeping every reading
--          in one ever-growing table wastes space. A circular buffer keeps exactly N
--          slots per sensor and overwrites the oldest one using sequence MOD N.
-- Note: Each write is an UPSERT into slot (seq % N), so the table never grows past
--       sensors x N rows. In PostgreSQL each overwrite still creates a new row version,
--       so a low fillfactor helps HOT updates and autovacuum keeps the table small.
--       SQL Server's memory-optimised tables are the high-throughput option on that
--       platform; that is not shown here.
-- All data is fictional.

DROP TABLE IF EXISTS ring_buffer;

CREATE TABLE ring_buffer (
    sensor_id   text,
    slot_id     int,
    seq         bigint NOT NULL,
    reading     numeric(10,3) NOT NULL,
    recorded_at timestamptz NOT NULL,
    PRIMARY KEY (sensor_id, slot_id)
) WITH (fillfactor = 70);

-- Write 25 readings per sensor into a 10-slot buffer, one reading at a time as a
-- real ingest would (one UPSERT per reading)
DO $$
BEGIN
    FOR g IN 1..25 LOOP
        INSERT INTO ring_buffer AS rb (sensor_id, slot_id, seq, reading, recorded_at)
        SELECT s.sensor_id, g % 10, g, round((300 + g * 0.5)::numeric, 3),
               timestamptz '2026-11-01 08:00' + g * interval '1 second'
        FROM (VALUES ('TURBINE_PSI'), ('OIL_TEMP')) s(sensor_id)
        ON CONFLICT (sensor_id, slot_id) DO UPDATE
           SET seq = EXCLUDED.seq, reading = EXCLUDED.reading, recorded_at = EXCLUDED.recorded_at
           WHERE EXCLUDED.seq > rb.seq;     -- never overwrite a newer value with an older one
    END LOOP;
END $$;

-- The buffer holds only the latest 10 readings per sensor, in time order
SELECT sensor_id, seq, reading, recorded_at
FROM ring_buffer
ORDER BY sensor_id, seq;

SELECT sensor_id, count(*) AS slots_used, min(seq) AS oldest_seq, max(seq) AS newest_seq
FROM ring_buffer
GROUP BY sensor_id;

-- Expected: 2 sensors x 10 rows; seq 16 to 25 for each sensor.
