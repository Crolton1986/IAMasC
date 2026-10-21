-- 0001: base tables for slice 1. State, plans, runs, and requests arrive with slice 2.

-- Append-only record of everything IAMasC does or is asked to do.
CREATE TABLE audit (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    at             TEXT    NOT NULL,             -- UTC, ISO 8601
    actor          TEXT    NOT NULL,             -- signed-in user, 'system', or 'scheduler'
    action         TEXT    NOT NULL,             -- e.g. person.created, config.validated
    workspace      TEXT,
    target         TEXT,                         -- e.g. person/E-004611
    before_json    TEXT,
    after_json     TEXT,
    correlation_id TEXT                          -- ties together entries from one request or run
);
CREATE INDEX ix_audit_target ON audit (target, at);
CREATE INDEX ix_audit_at ON audit (at);

CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit
BEGIN
    SELECT RAISE(ABORT, 'audit is append-only');
END;

CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit
BEGIN
    SELECT RAISE(ABORT, 'audit is append-only');
END;

-- Latest HR record per person, as received from the HR source.
CREATE TABLE hr_cache (
    workspace   TEXT NOT NULL,
    employee_id TEXT NOT NULL,
    source      TEXT NOT NULL,
    data_json   TEXT NOT NULL,
    synced_at   TEXT NOT NULL,
    PRIMARY KEY (workspace, employee_id)
);

-- Web sign-in sessions (server-side store for Pode).
CREATE TABLE sessions (
    id         TEXT PRIMARY KEY,
    data_json  TEXT NOT NULL,
    expires_at TEXT NOT NULL
);
CREATE INDEX ix_sessions_expires ON sessions (expires_at);
