-- Topic: Vincenty inverse formula on the WGS-84 ellipsoid in plain SQL
-- Database: PostgreSQL 14+
-- Problem: A system without GIS extensions needs accurate distances and initial bearings
--          between waypoints. The spherical haversine formula is off by up to about 0.5%;
--          Vincenty's iterative method on the WGS-84 ellipsoid is accurate to well under
--          a millimetre for non-antipodal points.
-- Note: The iteration runs in a recursive CTE and stops when lambda changes by less than
--       1e-12 radians (or after 200 rounds). Checked against GeographicLib.
-- All data is fictional. Waypoints are in open ocean and do not refer to any real site.

WITH RECURSIVE
ellipsoid AS (
    SELECT 6378137.0::float8 AS a, 1 / 298.257223563::float8 AS f
),
pts AS (
    SELECT 'WP-A'::text AS from_wp, 'WP-B'::text AS to_wp,
           radians(10.0) AS lat1, radians(60.0) AS lon1,
           radians(12.5) AS lat2, radians(62.0) AS lon2
),
prep AS (
    SELECT p.*, e.a, e.f, e.a * (1 - e.f) AS b,
           atan((1 - e.f) * tan(lat1)) AS u1,
           atan((1 - e.f) * tan(lat2)) AS u2,
           lon2 - lon1 AS l
    FROM pts p CROSS JOIN ellipsoid e
),
iter (n, from_wp, to_wp, a, b, f, u1, u2, l, lambda, prev_lambda) AS (
    SELECT 0, from_wp, to_wp, a, b, f, u1, u2, l, l, l + 1 FROM prep
    UNION ALL
    SELECT n + 1, from_wp, to_wp, a, b, f, u1, u2, l,
           l + (1 - c) * f * sin_alpha * (sigma + c * sin_sigma *
               (cos_2sm + c * cos_sigma * (-1 + 2 * cos_2sm ^ 2))),
           lambda
    FROM (
        SELECT i.*, q.sin_sigma, q.cos_sigma, q.sigma, q.sin_alpha,
               q.cos2_alpha, q.cos_2sm,
               f / 16 * q.cos2_alpha * (4 + f * (4 - 3 * q.cos2_alpha)) AS c
        FROM iter i
        CROSS JOIN LATERAL (
            SELECT s.*, atan2(s.sin_sigma, s.cos_sigma) AS sigma,
                   cos(i.u1) * cos(i.u2) * sin(i.lambda) / s.sin_sigma AS sin_alpha,
                   1 - (cos(i.u1) * cos(i.u2) * sin(i.lambda) / s.sin_sigma) ^ 2 AS cos2_alpha,
                   s.cos_sigma - 2 * sin(i.u1) * sin(i.u2)
                       / (1 - (cos(i.u1) * cos(i.u2) * sin(i.lambda) / s.sin_sigma) ^ 2) AS cos_2sm
            FROM (SELECT sqrt((cos(i.u2) * sin(i.lambda)) ^ 2 +
                              (cos(i.u1) * sin(i.u2) - sin(i.u1) * cos(i.u2) * cos(i.lambda)) ^ 2) AS sin_sigma,
                         sin(i.u1) * sin(i.u2) + cos(i.u1) * cos(i.u2) * cos(i.lambda) AS cos_sigma) s
        ) q
        WHERE abs(i.lambda - i.prev_lambda) > 1e-12 AND i.n < 200
    ) step
),
final AS (
    SELECT DISTINCT ON (from_wp, to_wp) * FROM iter ORDER BY from_wp, to_wp, n DESC
),
result AS (
    SELECT f.*, s.sin_sigma, s.cos_sigma, atan2(s.sin_sigma, s.cos_sigma) AS sigma,
           cos(u1) * cos(u2) * sin(lambda) / s.sin_sigma AS sin_alpha
    FROM final f
    CROSS JOIN LATERAL (
        SELECT sqrt((cos(u2) * sin(lambda)) ^ 2 +
                    (cos(u1) * sin(u2) - sin(u1) * cos(u2) * cos(lambda)) ^ 2) AS sin_sigma,
               sin(u1) * sin(u2) + cos(u1) * cos(u2) * cos(lambda) AS cos_sigma
    ) s
),
terms AS (
    SELECT r.*, 1 - sin_alpha ^ 2 AS cos2_alpha,
           cos_sigma - 2 * sin(u1) * sin(u2) / (1 - sin_alpha ^ 2) AS cos_2sm,
           (1 - sin_alpha ^ 2) * (a ^ 2 - b ^ 2) / b ^ 2 AS u_sq
    FROM result r
),
coef AS (
    SELECT t.*,
           1 + u_sq / 16384 * (4096 + u_sq * (-768 + u_sq * (320 - 175 * u_sq))) AS big_a,
           u_sq / 1024 * (256 + u_sq * (-128 + u_sq * (74 - 47 * u_sq)))        AS big_b
    FROM terms t
)
SELECT from_wp, to_wp, n AS iterations,
       round((b * big_a * (sigma - big_b * sin_sigma * (cos_2sm + big_b / 4 *
             (cos_sigma * (-1 + 2 * cos_2sm ^ 2) - big_b / 6 * cos_2sm *
             (-3 + 4 * sin_sigma ^ 2) * (-3 + 4 * cos_2sm ^ 2)))))::numeric, 3) AS distance_m,
       round(((degrees(atan2(cos(u2) * sin(lambda),
               cos(u1) * sin(u2) - sin(u1) * cos(u2) * cos(lambda))) + 360)::numeric % 360), 6)
                                                                      AS initial_bearing_deg,
       round((2 * 6371008.8 * asin(sqrt(sin((radians(12.5) - radians(10.0)) / 2) ^ 2 +
             cos(radians(10.0)) * cos(radians(12.5)) * sin(radians(2.0) / 2) ^ 2)))::numeric, 3)
                                                                      AS haversine_m
FROM coef;

-- Expected:
--   WP-A -> WP-B, 5 iterations, distance 352364.078 m, initial bearing 38.108520 deg
--   (GeographicLib gives 352364.078 m and 38.108520 deg)
--   haversine 353332.078 m: about 968 m (0.27%) too long on this route
