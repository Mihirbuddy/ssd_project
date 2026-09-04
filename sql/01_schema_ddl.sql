-- 01_schema_ddl.sql
-- Project 4: CareConnect — On-Demand Telemedicine
-- Structured (PostgreSQL) schema



CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

DROP MATERIALIZED VIEW IF EXISTS clinic_monthly_discharges;

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


/*select * from wallet_audit_logs limit 100;
select * from patients LIMIT 10;

UPDATE patients SET hsa_balance = hsa_balance - 25.00 WHERE id = '4b080274-b443-4a66-88c5-917ba8e63d62';
select * from wallet_audit_logs where patient_id='4b080274-b443-4a66-88c5-917ba8e63d62';

CALL book_appointment('0024ca1a-a1ce-4437-b65a-170ffc8fb3bd', 
'31a14f8c-dd5e-42aa-b32e-4a68a9cc06d7', 50.00);

SELECT * from wallet_audit_logs where patient_id='0024ca1a-a1ce-4437-b65a-170ffc8fb3bd';


SELECT count(*) FROM patients p
WHERE NOT EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.patient_id = p.id
      AND a.status IN ('WAITING', 'IN_CONSULTATION')
);

select patient_id, count(DISTINCT status) from appointments
GROUP BY patient_id HAVING COUNT(DISTINCT status)=1;

select * from appointments where id='0024ca1a-a1ce-4437-b65a-170ffc8fb3bd';
select * from clinics where is_accepting_patients=True limit 100;*/
