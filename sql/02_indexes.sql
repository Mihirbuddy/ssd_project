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
