-- 02_indexes.sql
-- Supporting indexes + the partial unique index constraint
-- ---------------------------------------------------------------------------
-- Refinements vs. the original draft:
-- 1. idx_appointments_clinic (clinic_id) alone has been DROPPED. A B-tree
--    index on (clinic_id, created_at) already satisfies any query that
--    filters on clinic_id by itself, via the leftmost-prefix rule — so a
--    separate single-column index on clinic_id was pure redundant
--    write/storage overhead.
-- 2. idx_appointments_patient (patient_id) is KEPT even though
--    idx_active_consult also leads with patient_id. That index is
--    PARTIAL (WHERE status IN ('WAITING','IN_CONSULTATION')), so the
--    planner can't use it for a query that needs to see DISCHARGED rows
--    too (e.g. a patient's full appointment history, or the ON DELETE
--    RESTRICT check when deleting a patient). A full index is still
--    required for those.
-- 3. wallet_audit_logs now gets a composite (patient_id, logged_at DESC)
--    index instead of a bare patient_id index, since the only realistic
--    query against this table is "this patient's ledger, most recent
--    first."
-- ---------------------------------------------------------------------------

-- FK / lookup indexes
CREATE INDEX idx_appointments_patient      ON appointments(patient_id);
CREATE INDEX idx_wallet_audit_patient_time ON wallet_audit_logs(patient_id, logged_at DESC);

-- Prevent a patient from having more than one concurrently-active appointment.
-- Enforced here rather than as a CHECK precisely because a partial unique
-- index is race-free under MVCC: Postgres aborts the second of two
-- concurrent INSERTs that would violate it, at commit time, no matter how
-- the transactions interleave. See 01_schema_ddl.sql for why a CHECK
-- can't do this.
CREATE UNIQUE INDEX idx_active_consult
ON appointments (patient_id)
WHERE status IN ('WAITING', 'IN_CONSULTATION');

-- Speeds up the moving-average window query (Workflow 2), which groups by
-- clinic_id and filters/orders by created_at (date). Also serves any
-- "appointments for clinic X" query on its own (leftmost prefix), which is
-- why the separate single-column clinic_id index above was removed.
CREATE INDEX idx_appointments_clinic_created
ON appointments (clinic_id, created_at);
