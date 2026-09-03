-- 01_schema_ddl.sql
-- Project 4: CareConnect — On-Demand Telemedicine
-- Structured (PostgreSQL) schema
-- ---------------------------------------------------------------------------
-- ASSUMPTIONS (documented per assignment instructions):
-- 1. The generic spec's "wallet_balance" maps to "hsa_balance" for this
--    domain (patients pay copays out of an HSA-style balance).
-- 2. IDs are UUIDs (gen_random_uuid()) rather than serial ints.
-- 3. Consistency between wallet_audit_logs.balance_after and the *current*
--    patients.hsa_balance CANNOT be expressed as a CHECK constraint:
--    Postgres CHECK constraints may only reference columns within the same
--    row being inserted/updated — they cannot run a subquery against
--    another table (or another row) and have it stay valid under
--    concurrent writes. This consistency is guaranteed procedurally
--    instead: the AFTER UPDATE trigger in 03_triggers_and_audit.sql and
--    sp_execute_appointment in 04_stored_procedures.sql are the only code
--    paths that touch hsa_balance, and each writes the ledger row and the
--    balance update inside the same transaction.
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

CREATE TABLE patients (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(120) NOT NULL,
    hsa_balance  DECIMAL(10,2) NOT NULL DEFAULT 0.00
                 CHECK (hsa_balance >= 0.00)
);

CREATE TABLE wallet_audit_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id     UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    amount_changed DECIMAL(10,2) NOT NULL,
    action_type    VARCHAR(10) NOT NULL
                   CHECK (action_type IN ('CREDIT', 'DEBIT')),
    balance_after  DECIMAL(10,2) NOT NULL
                   CHECK (balance_after >= 0.00),
    logged_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- keeps the ledger internally consistent: a CREDIT can't carry a
    -- negative amount and a DEBIT can't carry a positive one
    CONSTRAINT chk_amount_sign_matches_type CHECK (
        (action_type = 'CREDIT' AND amount_changed > 0) OR
        (action_type = 'DEBIT'  AND amount_changed < 0)
    )
);
-- This table is meant to be written ONLY by the trigger on patients
-- (03_triggers_and_audit.sql). In a real deployment you'd
-- REVOKE INSERT, UPDATE, DELETE ON wallet_audit_logs FROM app_role;
-- so the application can never bypass the trigger — no CHECK constraint
-- can express "only a trigger may write here."

CREATE TABLE clinics (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                  VARCHAR(150) NOT NULL,
    latitude              DOUBLE PRECISION NOT NULL
                           CHECK (latitude BETWEEN -90 AND 90),
    longitude             DOUBLE PRECISION NOT NULL
                           CHECK (longitude BETWEEN -180 AND 180),
    is_accepting_patients BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE appointments (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id    UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    clinic_id     UUID NOT NULL REFERENCES clinics(id) ON DELETE RESTRICT,
    copay_amount  DECIMAL(10,2) NOT NULL CHECK (copay_amount >= 0.00),
    status        VARCHAR(20) NOT NULL DEFAULT 'WAITING'
                  CHECK (status IN ('WAITING', 'IN_CONSULTATION', 'DISCHARGED')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- NOTE: "no more than one concurrently-active appointment per patient" is
-- deliberately NOT enforced with a CHECK + subquery
-- (e.g. CHECK ((SELECT count(*) FROM appointments WHERE ...) <= 1)):
--   (a) Postgres doesn't allow subqueries in CHECK constraints at all, and
--   (b) even a trigger-based COUNT(*) re-check would be racy — two
--       concurrent transactions can both pass the count check before
--       either commits.
-- The race-free fix is the partial UNIQUE INDEX idx_active_consult in
-- 02_indexes.sql, which Postgres enforces atomically at commit time
-- regardless of how concurrent transactions interleave.
