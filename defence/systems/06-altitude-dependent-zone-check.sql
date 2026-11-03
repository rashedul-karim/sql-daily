-- Topic: Altitude-dependent threat envelopes - which aircraft are inside a no-fly zone
-- Database: PostgreSQL 14+ (no extensions needed)
-- Problem: A restricted zone's effective radius depends on aircraft altitude: wider at
--          high altitude, narrower at low altitude. For each aircraft position, compute the
--          great-circle distance to each zone centre and flag the ones inside the envelope.
-- Note: Distance uses the haversine formula on a spherical Earth (radius 3440.065 nm),
--       accurate to about 0.5%, enough for zone checks. PostGIS ST_DWithin on geography
--       is the production choice; this file shows the maths in plain SQL.
-- All data is fictional. Coordinates are in open ocean and do not refer to any real site.

DROP TABLE IF EXISTS threat_zones, aircraft_positions;

CREATE TABLE threat_zones (
    zone_id        text PRIMARY KEY,
    lat            double precision NOT NULL,
    lon            double precision NOT NULL,
    base_range_nm  numeric(6,2) NOT NULL
);

CREATE TABLE aircraft_positions (
    tail_no text,
    lat     double precision,
    lon     double precision,
    alt_ft  int
);

INSERT INTO threat_zones VALUES ('ZONE-ALPHA', 10.000, 60.000, 25.0);

INSERT INTO aircraft_positions VALUES
    ('TR-101', 10.000, 60.500, 28000),   -- ~29.6 nm east, high
    ('TR-102', 10.000, 60.300,   800),   -- ~17.7 nm east, low
    ('TR-103', 10.000, 60.350, 15000);   -- ~20.7 nm east, medium

WITH envelope AS (
    SELECT z.zone_id, a.tail_no, a.alt_ft,
           CASE WHEN a.alt_ft > 25000 THEN z.base_range_nm * 1.4
                WHEN a.alt_ft < 1000  THEN z.base_range_nm * 0.5
                ELSE z.base_range_nm END AS effective_radius_nm,
           2 * 3440.065 * asin(sqrt(
               power(sin(radians(a.lat - z.lat) / 2), 2) +
               cos(radians(z.lat)) * cos(radians(a.lat)) *
               power(sin(radians(a.lon - z.lon) / 2), 2)))  AS distance_nm
    FROM threat_zones z CROSS JOIN aircraft_positions a
)
SELECT zone_id, tail_no, alt_ft,
       effective_radius_nm,
       round(distance_nm::numeric, 1)                       AS distance_nm,
       distance_nm <= effective_radius_nm                    AS inside_zone
FROM envelope
ORDER BY tail_no;

-- Expected:
--   TR-101  28000 ft  radius 35.0  distance 29.6  inside  (high altitude widens the zone)
--   TR-102    800 ft  radius 12.5  distance 17.7  outside (low altitude narrows it)
--   TR-103  15000 ft  radius 25.0  distance 20.7  inside
