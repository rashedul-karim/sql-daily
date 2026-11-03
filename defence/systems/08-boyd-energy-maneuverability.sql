-- Topic: Boyd Energy-Maneuverability formulation (Specific Excess Power Ps) in SQL
-- Database: PostgreSQL 14+, SQL Server 2016+
-- Problem: John Boyd's Energy-Maneuverability theory calculates an aircraft's rate of energy change
--          Ps = V * (T - D) / W. Calculate instantaneous energy states and specific excess power
--          from flight recorder tables using non-iterative window functions.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS flight_recorder_telemetry (
    sample_id   BIGSERIAL PRIMARY KEY,
    tail_no     VARCHAR(16) NOT NULL,
    sample_time TIMESTAMPTZ NOT NULL,
    velocity_mps NUMERIC(8,2) NOT NULL,
    altitude_m   NUMERIC(8,2) NOT NULL
);

TRUNCATE TABLE flight_recorder_telemetry;
INSERT INTO flight_recorder_telemetry (tail_no, sample_time, velocity_mps, altitude_m) VALUES
('TR-101', '2026-05-01 10:00:00+06', 220.0, 5000.0),
('TR-101', '2026-05-01 10:00:05+06', 235.0, 5150.0),
('TR-101', '2026-05-01 10:00:10+06', 250.0, 5320.0);

WITH energy_calc AS (
    SELECT tail_no, sample_time, velocity_mps, altitude_m,
           -- Specific energy Es = h + V^2 / (2g), g = 9.80665 m/s^2
           altitude_m + (velocity_mps * velocity_mps) / (2.0 * 9.80665) AS specific_energy_meters,
           EXTRACT(EPOCH FROM (sample_time - LAG(sample_time) OVER (PARTITION BY tail_no ORDER BY sample_time))) AS dt
    FROM flight_recorder_telemetry
)
SELECT tail_no, sample_time, ROUND(specific_energy_meters, 1) AS specific_energy_m,
       ROUND(((specific_energy_meters - LAG(specific_energy_meters) OVER (ORDER BY sample_time)) / dt)::numeric, 2) AS specific_excess_power_mps
FROM energy_calc;
