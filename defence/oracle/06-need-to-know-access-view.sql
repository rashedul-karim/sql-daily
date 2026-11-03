-- Topic: Need-to-know row access with classification levels and SYS_CONTEXT
-- Database: Oracle 19c+
-- Problem: Maintenance documents carry a classification (1 = UNCLASSIFIED up to
--          4 = SECRET) and belong to a unit. A user may read a document only if their
--          clearance is at least the document's level AND they belong to that unit
--          (or hold a cross-unit role). The application connects with one pooled
--          database account, so the real user is passed as the client identifier.
--          Users must also be unable to write a document above their own clearance.
-- Note: SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER') is set per session by the app with
--       DBMS_SESSION.SET_IDENTIFIER, which suits connection pools. A view filters rows
--       through one access function; WITH CHECK OPTION rejects inserts and updates through
--       the view that would create rows the user could not see. A function call per row
--       is fine for a demo. In production, Virtual Private Database (DBMS_RLS) applies
--       the rule to the base table itself, so nobody can bypass it, and it is faster.
-- All data is fictional.

BEGIN EXECUTE IMMEDIATE 'DROP VIEW v_documents';            EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP FUNCTION can_access';      EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE documents PURGE';       EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE user_clearance PURGE';  EXCEPTION WHEN OTHERS THEN NULL; END;
/

CREATE TABLE user_clearance (
    username      VARCHAR2(30) PRIMARY KEY,
    unit          VARCHAR2(10),
    clearance     NUMBER(1),
    cross_unit    CHAR(1) DEFAULT 'N'
);

CREATE TABLE documents (
    doc_id         NUMBER PRIMARY KEY,
    unit           VARCHAR2(10),
    classification NUMBER(1) CHECK (classification BETWEEN 1 AND 4),
    title          VARCHAR2(100)
);

INSERT INTO user_clearance VALUES ('TECH_ANIK',  'SQN-A', 2, 'N');
INSERT INTO user_clearance VALUES ('ENG_OFFR',   'SQN-A', 3, 'N');
INSERT INTO user_clearance VALUES ('QA_AUDITOR', 'HQ',    3, 'Y');

INSERT INTO documents VALUES (1, 'SQN-A', 1, 'Tool control checklist');
INSERT INTO documents VALUES (2, 'SQN-A', 2, 'Engine run-up procedure');
INSERT INTO documents VALUES (3, 'SQN-A', 3, 'Fleet defect trend report');
INSERT INTO documents VALUES (4, 'SQN-B', 2, 'Hangar shift plan');
INSERT INTO documents VALUES (5, 'SQN-B', 4, 'Restricted capability note');
COMMIT;

-- Access rule in one place. Kept as a function (not a subquery in the view) because
-- WITH CHECK OPTION is not reliably enforced through subqueries in the view's WHERE clause.
CREATE OR REPLACE FUNCTION can_access (p_unit VARCHAR2, p_class NUMBER)
RETURN NUMBER
IS
    v_ok NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_ok
    FROM user_clearance u
    WHERE u.username  = SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER')
      AND u.clearance >= p_class
      AND (u.unit = p_unit OR u.cross_unit = 'Y');
    RETURN v_ok;
END;
/

CREATE OR REPLACE VIEW v_documents AS
SELECT d.doc_id, d.unit, d.classification, d.title
FROM documents d
WHERE can_access(d.unit, d.classification) = 1
WITH CHECK OPTION;

-- Technician: SQN-A only, up to level 2  -> docs 1, 2
BEGIN DBMS_SESSION.SET_IDENTIFIER('TECH_ANIK'); END;
/
SELECT doc_id, unit, classification, title FROM v_documents ORDER BY doc_id;

-- Engineering officer: SQN-A, up to level 3 -> docs 1, 2, 3
BEGIN DBMS_SESSION.SET_IDENTIFIER('ENG_OFFR'); END;
/
SELECT doc_id, unit, classification, title FROM v_documents ORDER BY doc_id;

-- QA auditor: all units, up to level 3 -> docs 1, 2, 3, 4 (never 5)
BEGIN DBMS_SESSION.SET_IDENTIFIER('QA_AUDITOR'); END;
/
SELECT doc_id, unit, classification, title FROM v_documents ORDER BY doc_id;

-- Write-up attempt: technician tries to file a level-3 document through the view.
-- Fails with ORA-01402: view WITH CHECK OPTION where-clause violation.
BEGIN DBMS_SESSION.SET_IDENTIFIER('TECH_ANIK'); END;
/
INSERT INTO v_documents VALUES (6, 'SQN-A', 3, 'Should be rejected');
ROLLBACK;

-- No identifier set (for example a misconfigured app) -> sees nothing: fail closed.
BEGIN DBMS_SESSION.CLEAR_IDENTIFIER; END;
/
SELECT COUNT(*) AS visible_docs FROM v_documents;

-- Hardening for real use:
--   1. Grant users SELECT on the view only, never on the base table.
--   2. Move the rule into a VPD policy (DBMS_RLS.ADD_POLICY). The policy returns a predicate
--      string that Oracle appends to every query, so it applies everywhere and is optimized.
--   3. Audit reads of high-classification rows with Unified Auditing or fine-grained auditing.
-- SQL Server equivalent: Row-Level Security (CREATE SECURITY POLICY) with SESSION_CONTEXT.
