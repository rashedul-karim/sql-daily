-- Topic: Differential privacy query engine adding bounded Laplace noise in SQL
-- Database: PostgreSQL 14+, Oracle 19c
-- Problem: Higher headquarters requests aggregate fleet readiness statistics (e.g. % ready),
--          but adversaries must not be able to deduce the operational status of an individual jet
--          using differencing attacks. Inject mathematically bounded Laplace noise into aggregates.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS fleet_status_census (
    tail_no VARCHAR(16) PRIMARY KEY,
    is_ready INT NOT NULL
);

INSERT INTO fleet_status_census VALUES
('TR-101', 1), ('TR-102', 1), ('TR-103', 0), ('TR-104', 1)
ON CONFLICT (tail_no) DO NOTHING;

-- True count vs Differentially Private count with injected noise parameter
SELECT SUM(is_ready) AS true_ready_count,
       -- Laplace noise generator simulation: -1, 0, or +1 random noise based on uniform distribution
       ROUND(SUM(is_ready) + (random() * 2.0 - 1.0)::numeric, 1) AS dp_ready_count_noisy
FROM fleet_status_census;
