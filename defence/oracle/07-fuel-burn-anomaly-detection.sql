-- Topic: Fuel burn anomaly detection - z-score and robust median/MAD in SQL
-- Database: Oracle 19c+
-- Problem: Each sortie records fuel used and flight time. Burn rate (kg per hour)
--          should be stable per aircraft type and mission profile. Flag sorties whose
--          burn rate is unusual compared with similar sorties: a possible leak, a
--          recording error, or an engine that needs attention.
--          Compare two methods: mean/standard deviation (z-score) and median/MAD.
-- Note: A single bad value inflates the mean and standard deviation, which can hide the
--       very outlier you are looking for (masking). Median and MAD (median absolute
--       deviation) are robust. Rule of thumb: |x - median| / (1.4826 * MAD) > 3 is an outlier.
--       All of this runs as analytic functions, no export to Python needed.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE sorties PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE sorties (
    sortie_id   NUMBER PRIMARY KEY,
    tail_no     VARCHAR2(10),
    profile     VARCHAR2(15),     -- TRAINING, NAVIGATION
    flight_hrs  NUMBER(4,2),
    fuel_kg     NUMBER(6)
);

-- Normal sorties: TRAINING ~ 300 kg/h, NAVIGATION ~ 250 kg/h, with small noise
INSERT INTO sorties
SELECT LEVEL,
       'TR-10' || MOD(LEVEL, 4),
       CASE WHEN MOD(LEVEL, 3) = 0 THEN 'NAVIGATION' ELSE 'TRAINING' END,
       1.5 + MOD(LEVEL, 5) * 0.25,
       ROUND((1.5 + MOD(LEVEL, 5) * 0.25)
             * CASE WHEN MOD(LEVEL, 3) = 0 THEN 250 ELSE 300 END
             * (1 + (MOD(LEVEL * 7, 11) - 5) / 100))
FROM dual CONNECT BY LEVEL <= 60;

-- Anomalies
UPDATE sorties SET fuel_kg = fuel_kg * 1.35 WHERE sortie_id = 14;   -- high burn
UPDATE sorties SET fuel_kg = fuel_kg * 10   WHERE sortie_id = 22;   -- typing error (extra 0)
UPDATE sorties SET fuel_kg = fuel_kg * 1.30 WHERE sortie_id = 31;   -- high burn
COMMIT;

WITH rates AS (
    SELECT s.*, fuel_kg / flight_hrs AS burn_rate
    FROM sorties s
),
stats AS (
    SELECT r.*,
           AVG(burn_rate)    OVER (PARTITION BY profile)                  AS mean_rate,
           STDDEV(burn_rate) OVER (PARTITION BY profile)                  AS sd_rate,
           MEDIAN(burn_rate) OVER (PARTITION BY profile)                  AS med_rate
    FROM rates r
),
mad AS (
    SELECT st.*,
           MEDIAN(ABS(burn_rate - med_rate)) OVER (PARTITION BY profile)  AS mad_rate
    FROM stats st
)
SELECT sortie_id, tail_no, profile,
       ROUND(burn_rate)                                                AS kg_per_hr,
       ROUND(med_rate)                                                 AS median_kg_hr,
       ROUND((burn_rate - mean_rate) / NULLIF(sd_rate, 0), 2)          AS z_score,
       ROUND((burn_rate - med_rate) / NULLIF(1.4826 * mad_rate, 0), 2) AS robust_z,
       CASE WHEN ABS((burn_rate - mean_rate) / NULLIF(sd_rate, 0)) > 3
            THEN 'Y' END                                               AS flag_z,
       CASE WHEN ABS((burn_rate - med_rate) / NULLIF(1.4826 * mad_rate, 0)) > 3
            THEN 'Y' END                                               AS flag_robust
FROM mad
WHERE ABS((burn_rate - med_rate) / NULLIF(1.4826 * mad_rate, 0)) > 3
   OR ABS((burn_rate - mean_rate) / NULLIF(sd_rate, 0)) > 3
ORDER BY ABS((burn_rate - med_rate) / NULLIF(1.4826 * mad_rate, 0)) DESC;

-- What to look for in the output:
--   Sortie 22 (the extra zero) is caught by both methods.
--   Sorties 14 and 31 (30-35% high burn) are caught by the robust method, while the
--   huge error in sortie 22 inflates the standard deviation so the z-score misses them.
--   That is masking, and why robust statistics are the safer default for data quality checks.
--   Expected values (TRAINING profile): sortie 22 z 6.15 / robust 193;
--   sortie 14 z 0.14 / robust 9.5; sortie 31 z 0.08 / robust 7.7.
--
-- Dialects: SQL Server has no MEDIAN; use PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY x)
-- OVER (PARTITION BY ...). PostgreSQL has percentile_cont as an aggregate only, not a window.
