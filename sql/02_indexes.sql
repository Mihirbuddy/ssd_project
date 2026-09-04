-- 02_indexes.sql
-- Supporting indexes + the partial unique index constraint

-- FK / lookup indexes
CREATE INDEX idx_appointments_patient      ON appointments(patient_id);
CREATE INDEX idx_wallet_audit_patient_time ON wallet_audit_logs(patient_id, logged_at DESC);

CREATE UNIQUE INDEX idx_active_consult
ON appointments (patient_id)
WHERE status IN ('WAITING', 'IN_CONSULTATION');

CREATE INDEX idx_appointments_clinic_created
ON appointments (clinic_id, created_at);

-- Covering index to enable Index Only Scan for Window Analytics
-- CORRECTED: created_at is now the leading column to match the WHERE clause
CREATE INDEX idx_appointments_discharged_analytics 
ON appointments (created_at, clinic_id) 
INCLUDE (copay_amount);