-- Topic: 4D Spatio-Temporal Flight Path Collision Detection (X, Y, Z, t)
-- Database: PostgreSQL 15+ with PostGIS
-- Problem: Evaluating aircraft deconfliction in 3D produces false positives for flight paths
--          that cross the same waypoint 20 minutes apart. Implement 4D bounding hypercube queries
--          combining 3D spatial distance and temporal proximity thresholds (< 30 seconds).
-- All data is fictional.

CREATE TABLE IF NOT EXISTS flight_waypoints_4d (
    waypoint_id   BIGSERIAL PRIMARY KEY,
    tail_no       VARCHAR(16) NOT NULL,
    latitude      NUMERIC(9,6) NOT NULL,
    longitude     NUMERIC(9,6) NOT NULL,
    altitude_ft   INT NOT NULL,
    fix_time      TIMESTAMPTZ NOT NULL
);

TRUNCATE TABLE flight_waypoints_4d;

INSERT INTO flight_waypoints_4d (tail_no, latitude, longitude, altitude_ft, fix_time) VALUES
('TR-101', 23.8103, 90.4125, 25000, '2026-04-10 10:15:00+06'),
('TR-102', 23.8150, 90.4180, 25200, '2026-04-10 10:15:15+06'), -- near collision (< 30s, < 1NM, < 500ft)
('TR-103', 23.8103, 90.4125, 25000, '2026-04-10 10:45:00+06'); -- same spot 30 mins later (safe)

-- Find conflicts: lateral dist < 0.01 deg (~0.6 NM), altitude < 500 ft, time diff < 30s
SELECT a.tail_no AS ac1, b.tail_no AS ac2, a.fix_time,
       ROUND(ABS(a.altitude_ft - b.altitude_ft), 0) AS alt_separation_ft,
       ROUND(EXTRACT(EPOCH FROM (b.fix_time - a.fix_time))::numeric, 1) AS time_separation_sec
FROM flight_waypoints_4d a
JOIN flight_waypoints_4d b ON a.tail_no < b.tail_no
                          AND ABS(a.altitude_ft - b.altitude_ft) <= 500
                          AND ABS(EXTRACT(EPOCH FROM (a.fix_time - b.fix_time))) <= 30
                          AND ABS(a.latitude - b.latitude) <= 0.01
                          AND ABS(a.longitude - b.longitude) <= 0.01;
