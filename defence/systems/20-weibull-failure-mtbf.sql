-- Topic: Non-parametric Weibull hazard rate & Mean Time Between Failures (MTBF)
-- Database: PostgreSQL 14+, Oracle 19c, SQL Server 2016+
-- Problem: Preventative maintenance: predict aircraft hydraulic pump failure probabilities
--          based on operating hours using two-parameter Weibull distribution in pure SQL.
-- All data is fictional.

CREATE TABLE IF NOT EXISTS component_failure_samples (
    component_id VARCHAR(32) PRIMARY KEY,
    operating_hours NUMERIC(10,2) NOT NULL,
    failed INT NOT NULL -- 1 if failed, 0 if censored (still running)
);

INSERT INTO component_failure_samples VALUES
('PUMP-001', 450.0, 1),
('PUMP-002', 820.0, 1),
('PUMP-003', 1150.0, 1),
('PUMP-004', 1400.0, 0)
ON CONFLICT (component_id) DO NOTHING;

-- Rank failures using Bernard's approximation: F(i) = (i - 0.3) / (N + 0.4)
WITH ranked AS (
    SELECT component_id, operating_hours,
           ROW_NUMBER() OVER (ORDER BY operating_hours) AS i,
           COUNT(*) OVER () AS n
    FROM component_failure_samples
    WHERE failed = 1
)
SELECT component_id, operating_hours,
       ROUND(((i - 0.3) / (n + 0.4))::numeric, 4) AS cumulative_failure_probability
FROM ranked;
