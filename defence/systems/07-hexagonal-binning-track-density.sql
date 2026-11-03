-- Topic: Hexagonal binning of position reports to find traffic hot spots
-- Database: PostgreSQL 14+
-- Problem: Count aircraft position reports per area to find dense areas. Square grid
--          cells have neighbours at two different distances (sides and corners); hexagons
--          have six neighbours at equal distance, so density maps look smoother and fairer.
-- Note: Positions are projected to local x/y kilometres around a reference point
--       (equirectangular, fine over a few hundred km), then assigned to pointy-top hexagons
--       with axial coordinates (q, r) and cube rounding. Uber's H3 library does this
--       globally; this file shows the method in plain SQL.
-- All data is fictional. Positions are in open ocean and do not refer to any real site.

DROP TABLE IF EXISTS position_reports;
CREATE TABLE position_reports (tail_no text, lat double precision, lon double precision);

-- 300 synthetic reports: a dense cluster plus scattered traffic
INSERT INTO position_reports
SELECT 'TR-' || (100 + g % 12),
       10.0 + CASE WHEN g % 3 = 0 THEN (random() - 0.5) * 0.15 ELSE (random() - 0.5) * 1.2 END,
       60.0 + CASE WHEN g % 3 = 0 THEN (random() - 0.5) * 0.15 ELSE (random() - 0.5) * 1.2 END
FROM generate_series(1, 300) g;

WITH params AS (
    SELECT 10.0::float8 AS ref_lat, 60.0::float8 AS ref_lon, 10.0::float8 AS hex_size_km
),
xy AS (                      -- project to local kilometres
    SELECT r.tail_no,
           (r.lon - p.ref_lon) * 111.320 * cos(radians(p.ref_lat)) AS x_km,
           (r.lat - p.ref_lat) * 110.574                           AS y_km,
           p.hex_size_km
    FROM position_reports r CROSS JOIN params p
),
frac AS (                    -- fractional axial coordinates (pointy-top hexagons)
    SELECT tail_no,
           (sqrt(3) / 3 * x_km - y_km / 3) / hex_size_km AS qf,
           (2.0 / 3 * y_km) / hex_size_km                AS rf
    FROM xy
),
cube AS (                    -- cube rounding: round all three, fix the one with the largest error
    SELECT tail_no, qf, rf, -qf - rf AS sf,
           round(qf) AS q0, round(rf) AS r0, round(-qf - rf) AS s0
    FROM frac
),
hex AS (
    SELECT tail_no,
           CASE WHEN abs(q0 - qf) > abs(r0 - rf) AND abs(q0 - qf) > abs(s0 - sf) THEN -r0 - s0 ELSE q0 END AS q,
           CASE WHEN abs(q0 - qf) > abs(r0 - rf) AND abs(q0 - qf) > abs(s0 - sf) THEN r0
                WHEN abs(r0 - rf) > abs(s0 - sf) THEN -q0 - s0 ELSE r0 END AS r
    FROM cube
)
SELECT q, r,
       count(*)                                AS reports,
       count(DISTINCT tail_no)                 AS aircraft,
       rank() OVER (ORDER BY count(*) DESC)    AS density_rank
FROM hex
GROUP BY q, r
ORDER BY reports DESC
LIMIT 5;

-- Expected: hexagon (0, 0) ranks first with roughly 100+ reports (the dense cluster);
-- the rest have a handful each. Exact counts vary because positions use random().
