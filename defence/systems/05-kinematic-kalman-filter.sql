-- Topic: Recursive discrete Kalman filter for radar track smoothing in pure SQL
-- Database: PostgreSQL 14+
-- Problem: Raw radar returns suffer from sensor noise and atmospheric jitter.
--          Filter position state transitions directly in SQL using recursive CTEs
--          to prevent round-trip application latency.
-- All data is fictional.

WITH RECURSIVE
measurements(step, z) AS (
    VALUES (1, 100.2), (2, 102.1), (3, 101.5), (4, 105.8), (5, 104.9), (6, 108.2)
),
kalman(step, z, x_est, p_est) AS (
    -- Initial state: measurement 1, state estimate = 100.0, error covariance P = 1.0
    SELECT 1, z, 100.0::numeric, 1.0::numeric
    FROM measurements WHERE step = 1
    UNION ALL
    SELECT m.step, m.z,
           -- Kalman Gain K = P / (P + R), where measurement variance R = 4.0
           -- Updated estimate = x + K * (z - x)
           ROUND((k.x_est + (k.p_est / (k.p_est + 4.0)) * (m.z - k.x_est))::numeric, 3),
           -- Updated covariance P = (1 - K) * P
           ROUND(((1.0 - (k.p_est / (k.p_est + 4.0))) * k.p_est + 0.1)::numeric, 3)
    FROM kalman k
    JOIN measurements m ON m.step = k.step + 1
)
SELECT step, z AS raw_radar_km, x_est AS smoothed_radar_km, p_est AS covariance_error
FROM kalman;
