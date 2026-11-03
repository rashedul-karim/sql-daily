-- Topic: Loading sortie logs without one bad row killing the batch
-- Database: Oracle 19c+
-- Problem: A nightly feed of sortie records arrives in a staging table. Some rows are bad:
--          a duplicate sortie ID, a flight time of zero, a tail number that does not exist.
--          The load must insert every good row, keep every bad row with its error message
--          for the data owner to fix, and report counts. Two standard Oracle approaches:
--          (A) DML error logging: one INSERT ... SELECT with LOG ERRORS
--          (B) PL/SQL BULK COLLECT + FORALL ... SAVE EXCEPTIONS for row-level control
-- Note: Without these, a single constraint violation rolls back the whole statement.
--       LOG ERRORS is set-based and fastest. FORALL SAVE EXCEPTIONS suits loads that need
--       procedural logic per batch. LIMIT keeps memory bounded on large feeds.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP TABLE err$_sortie_log PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE sortie_log PURGE';      EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE aircraft PURGE';        EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE stg_sortie PURGE';      EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE load_errors PURGE';     EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE aircraft (tail_no VARCHAR2(10) PRIMARY KEY);
INSERT INTO aircraft VALUES ('TR-101');
INSERT INTO aircraft VALUES ('TR-102');

CREATE TABLE sortie_log (
    sortie_id  NUMBER PRIMARY KEY,
    tail_no    VARCHAR2(10) NOT NULL REFERENCES aircraft,
    flown_on   DATE NOT NULL,
    flight_hrs NUMBER(4,2) CHECK (flight_hrs > 0)
);

CREATE TABLE stg_sortie AS
SELECT 1 sortie_id, 'TR-101' tail_no, DATE '2026-10-20' flown_on, 1.5 flight_hrs FROM dual UNION ALL
SELECT 2,           'TR-102',         DATE '2026-10-20',          2.0            FROM dual UNION ALL
SELECT 2,           'TR-102',         DATE '2026-10-21',          1.0            FROM dual UNION ALL -- duplicate id
SELECT 3,           'TR-999',         DATE '2026-10-21',          1.2            FROM dual UNION ALL -- unknown aircraft
SELECT 4,           'TR-101',         DATE '2026-10-22',          0              FROM dual UNION ALL -- zero hours
SELECT 5,           'TR-101',         NULL,                       1.1            FROM dual UNION ALL -- missing date
SELECT 6,           'TR-102',         DATE '2026-10-22',          1.7            FROM dual;
COMMIT;

------------------------------------------------------------------------------
-- (A) DML error logging
------------------------------------------------------------------------------
BEGIN
    DBMS_ERRLOG.CREATE_ERROR_LOG(dml_table_name => 'SORTIE_LOG');   -- creates ERR$_SORTIE_LOG
END;
/

INSERT INTO sortie_log (sortie_id, tail_no, flown_on, flight_hrs)
SELECT sortie_id, tail_no, flown_on, flight_hrs
FROM stg_sortie
LOG ERRORS INTO err$_sortie_log ('NIGHTLY-2026-10-22') REJECT LIMIT UNLIMITED;

COMMIT;

SELECT COUNT(*) AS loaded FROM sortie_log;

SELECT ora_err_number$ AS err_no,
       sortie_id, tail_no, flown_on, flight_hrs,
       SUBSTR(ora_err_mesg$, 1, 70) AS error_message
FROM err$_sortie_log
WHERE ora_err_tag$ = 'NIGHTLY-2026-10-22'
ORDER BY sortie_id;

------------------------------------------------------------------------------
-- (B) BULK COLLECT + FORALL SAVE EXCEPTIONS (reset and load again)
------------------------------------------------------------------------------
TRUNCATE TABLE sortie_log;

CREATE TABLE load_errors (
    sortie_id NUMBER,
    err_code  NUMBER,
    err_text  VARCHAR2(200),
    logged_at DATE DEFAULT SYSDATE
);

SET SERVEROUTPUT ON

DECLARE
    TYPE t_rows IS TABLE OF stg_sortie%ROWTYPE;
    v_rows     t_rows;
    v_loaded   PLS_INTEGER := 0;
    v_failed   PLS_INTEGER := 0;
    e_dml      EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_dml, -24381);       -- ORA-24381: error(s) in array DML

    CURSOR c IS SELECT * FROM stg_sortie;
BEGIN
    OPEN c;
    LOOP
        FETCH c BULK COLLECT INTO v_rows LIMIT 1000;
        EXIT WHEN v_rows.COUNT = 0;

        BEGIN
            FORALL i IN 1 .. v_rows.COUNT SAVE EXCEPTIONS
                INSERT INTO sortie_log VALUES v_rows(i);
            v_loaded := v_loaded + v_rows.COUNT;
        EXCEPTION
            WHEN e_dml THEN
                v_failed := v_failed + SQL%BULK_EXCEPTIONS.COUNT;
                v_loaded := v_loaded + v_rows.COUNT - SQL%BULK_EXCEPTIONS.COUNT;
                FOR j IN 1 .. SQL%BULK_EXCEPTIONS.COUNT LOOP
                    INSERT INTO load_errors (sortie_id, err_code, err_text)
                    VALUES (v_rows(SQL%BULK_EXCEPTIONS(j).ERROR_INDEX).sortie_id,
                            SQL%BULK_EXCEPTIONS(j).ERROR_CODE,
                            SQLERRM(-SQL%BULK_EXCEPTIONS(j).ERROR_CODE));
                END LOOP;
        END;
    END LOOP;
    CLOSE c;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Loaded: ' || v_loaded || ', rejected: ' || v_failed);
END;
/

SELECT sortie_id, err_code, SUBSTR(err_text, 1, 70) AS err_text
FROM load_errors
ORDER BY sortie_id;

-- Expected for both methods: 3 rows loaded (ids 1, 2, 6), 4 rejected:
--   duplicate id 2 (ORA-00001), unknown TR-999 (ORA-02291),
--   zero hours id 4 (ORA-02290), missing date id 5 (ORA-01400).
--
-- Dialects: SQL Server has no LOG ERRORS. The usual pattern is to validate in staging
-- first (anti-joins for missing parents, ROW_NUMBER for duplicates), route bad rows to
-- an error table, then insert only clean rows, all inside TRY...CATCH.
