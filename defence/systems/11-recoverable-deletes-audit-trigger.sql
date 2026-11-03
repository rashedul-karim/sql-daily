-- Topic: Making accidental deletes recoverable with an audit trigger
-- Database: PostgreSQL 14+
-- Problem: Someone runs DELETE without a WHERE clause on a schedule table before the
--          nightly backup. Restoring the whole database to get a few rows back is slow.
--          Capture every deleted row in an archive table, so rows can be restored with
--          one INSERT, and record who deleted them and when.
-- Note: Do not rely on "carving" deleted rows out of data pages: in PostgreSQL they remain
--       only until vacuum reuses the space, and InnoDB purges them in the background.
--       The real safety nets are this kind of trigger, point-in-time recovery from WAL
--       archives, and (in Oracle) Flashback Query.
-- All data is fictional.

DROP TABLE IF EXISTS flight_schedule, flight_schedule_deleted;
DROP FUNCTION IF EXISTS archive_deleted_schedule();

CREATE TABLE flight_schedule (
    record_id   int PRIMARY KEY,
    tail_no     text NOT NULL,
    sortie_slot text NOT NULL
);

CREATE TABLE flight_schedule_deleted (
    LIKE flight_schedule,
    deleted_at  timestamptz NOT NULL DEFAULT now(),
    deleted_by  text        NOT NULL DEFAULT current_user,
    txid        bigint      NOT NULL DEFAULT txid_current()
);

CREATE FUNCTION archive_deleted_schedule() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO flight_schedule_deleted (record_id, tail_no, sortie_slot)
    SELECT record_id, tail_no, sortie_slot FROM old_rows;
    RETURN NULL;
END $$;

-- Statement-level trigger with a transition table: one INSERT per DELETE statement,
-- not one per row, so a mass delete stays fast
CREATE TRIGGER trg_archive_deletes
AFTER DELETE ON flight_schedule
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION archive_deleted_schedule();

INSERT INTO flight_schedule VALUES
    (1, 'TR-101', '08:00-09:30'),
    (2, 'TR-102', '10:00-11:30'),
    (3, 'TR-103', '13:00-14:30');

-- The accident
DELETE FROM flight_schedule;

SELECT count(*) AS rows_left FROM flight_schedule;
SELECT record_id, tail_no, sortie_slot, deleted_by, txid FROM flight_schedule_deleted;

-- Recovery: restore everything removed by that one transaction
INSERT INTO flight_schedule (record_id, tail_no, sortie_slot)
SELECT record_id, tail_no, sortie_slot
FROM flight_schedule_deleted
WHERE txid = (SELECT max(txid) FROM flight_schedule_deleted)
ON CONFLICT (record_id) DO NOTHING;

SELECT * FROM flight_schedule ORDER BY record_id;

-- Expected: 0 rows left after the DELETE, 3 rows in the archive, all 3 restored.
