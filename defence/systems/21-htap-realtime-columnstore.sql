-- Topic: Real-Time HTAP workload isolation with Clustered Columnstore
-- Database: SQL Server 2017+ / PostgreSQL with columnar extensions
-- Problem: Running analytical readiness aggregations over 10 million rows locks operational
--          write streams. Isolate transactional row ingestion from columnar analytical scans.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS htap_telemetry_stream (
    telemetry_id BIGSERIAL PRIMARY KEY,
    tail_no      VARCHAR(16) NOT NULL,
    altitude_ft  INT NOT NULL,
    fuel_flow    NUMERIC(8,2) NOT NULL,
    logged_at    TIMESTAMPTZ DEFAULT clock_timestamp()
);

INSERT INTO htap_telemetry_stream (tail_no, altitude_ft, fuel_flow)
VALUES ('TR-101', 25000, 1420.5), ('TR-102', 32000, 1680.0);

-- Analytical aggregation without table locks
SELECT tail_no,
       COUNT(*) AS total_samples,
       AVG(altitude_ft) AS avg_altitude,
       AVG(fuel_flow) AS avg_fuel_flow
FROM htap_telemetry_stream
GROUP BY tail_no;
