-- Topic: Bell-LaPadula Multilevel Security (MLS) Mandatory Access Control (MAC) in RLS
-- Database: PostgreSQL 14+
-- Problem: Military security policy dictates Mandatory Access Control:
--          1) Simple Security: "No Read-Up" (user clearance >= row classification)
--          2) *-Property: "No Write-Down" (user clearance <= row classification)
--          Implement formal Bell-LaPadula access control using PostgreSQL Row-Level Security.
-- All data is fictional.

CREATE SCHEMA IF NOT EXISTS mls_security;
SET search_path TO mls_security, public;

DROP TABLE IF EXISTS operational_orders CASCADE;
CREATE TABLE operational_orders (
    order_id         BIGSERIAL PRIMARY KEY,
    mission_code     VARCHAR(32) NOT NULL,
    classification   INT NOT NULL, -- 1=UNCLASS, 2=RESTRICTED, 3=SECRET, 4=TOP_SECRET
    briefing_text    TEXT NOT NULL
);

INSERT INTO operational_orders VALUES
(1, 'ROUTINE-NAV', 1, 'Standard navigation flight plan.'),
(2, 'BORDER-PATROL', 3, 'Classified combat air patrol coordinates.');

-- Read rule: User can only see rows <= their clearance
-- Simulating a user with SECRET clearance (Level 3)
SELECT order_id, mission_code, classification, briefing_text
FROM operational_orders
WHERE classification <= 3; -- User clearance = 3
