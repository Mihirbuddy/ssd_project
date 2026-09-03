-- 01_schema_ddl.sql
-- Project 4: CareConnect — On-Demand Telemedicine
-- Structured (PostgreSQL) schema



CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS wallet_audit_logs;
DROP TABLE IF EXISTS clinics;
DROP TABLE IF EXISTS patients;

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
   
    CONSTRAINT chk_amount_sign_matches_type CHECK (
        (action_type = 'CREDIT' AND amount_changed > 0) OR
        (action_type = 'DEBIT'  AND amount_changed < 0)
    )
);


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

