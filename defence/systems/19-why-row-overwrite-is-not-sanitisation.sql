-- Topic: Why overwriting rows does NOT sanitise data in PostgreSQL
-- Database: PostgreSQL 14+ (needs the pageinspect extension, superuser on a test server)
-- Problem: A common belief is that UPDATE-ing sensitive values to zeros, then random
--          data, then dropping the table "shreds" them. In an MVCC database that is false:
--          each UPDATE writes a NEW row version and leaves the old one on the page until
--          vacuum, and even then the bytes are not wiped from the disk.
-- Note: Real media sanitisation (NIST SP 800-88: clear, purge, destroy) happens at the
--       storage level: encrypted storage with key destruction, device-level secure erase,
--       or physical destruction. The database cannot guarantee it.
-- All data is fictional.

CREATE EXTENSION IF NOT EXISTS pageinspect;

DROP TABLE IF EXISTS decommission_staging;
CREATE TABLE decommission_staging (id int, secret text) WITH (autovacuum_enabled = false);

INSERT INTO decommission_staging VALUES (1, 'FICTIONAL-CODEWORD-X');

-- The "three-pass overwrite"
UPDATE decommission_staging SET secret = repeat('0', 20);
UPDATE decommission_staging SET secret = repeat('F', 20);
UPDATE decommission_staging SET secret = md5(random()::text);

-- Look inside the table's first page: all four versions are still there
SELECT lp, t_xmin, t_xmax,
       convert_from(substring(t_data FROM 6), 'UTF8') AS stored_text
FROM heap_page_items(get_raw_page('decommission_staging', 0))
ORDER BY lp;

-- Expected: 4 tuples. The first still contains FICTIONAL-CODEWORD-X, marked dead by
-- t_xmax but physically present. VACUUM would mark that space reusable, not erase it.

DROP TABLE decommission_staging;
