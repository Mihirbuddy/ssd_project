-- 04_stored_procedures.sql
-- Workflow 1: atomically deduct HSA balance, create the appointment, and
-- log the audit trail (the audit row is produced automatically by
-- trg_wallet_audit from 03_triggers_and_audit.sql via the UPDATE below).

CREATE OR REPLACE PROCEDURE book_appointment(
    p_patient_id   UUID,
    p_clinic_id    UUID,
    p_copay_amount DECIMAL(10,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_balance DECIMAL(10,2);
    v_accepting       BOOLEAN;
BEGIN
    -- Lock the patient row for this transaction's duration to avoid a race
    -- between two concurrent bookings for the same patient.
    -- LOCK ORDERING: patients is always locked before clinics, in every
    -- procedure, so two sessions can never deadlock waiting on each other.
    SELECT hsa_balance INTO v_current_balance
    FROM patients
    WHERE id = p_patient_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Patient % not found', p_patient_id;
    END IF;

    -- FOR SHARE, not FOR UPDATE: we only read the flag, but it must not
    -- flip between this check and the INSERT below. A shared lock blocks
    -- an admin closing the clinic while still letting other bookings at
    -- the same clinic run in parallel.
    SELECT is_accepting_patients INTO v_accepting
    FROM clinics
    WHERE id = p_clinic_id
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Clinic % not found', p_clinic_id;
    END IF;

    IF NOT v_accepting THEN
        RAISE EXCEPTION 'Clinic % is not accepting patients', p_clinic_id;
    END IF;

    -- idx_active_consult is the real enforcement; this check just turns a
    -- raw unique-index violation into a readable business error.
    IF EXISTS (
        SELECT 1 FROM appointments
        WHERE patient_id = p_patient_id
          AND status IN ('WAITING', 'IN_CONSULTATION')
    ) THEN
        RAISE EXCEPTION 'Patient % already has an active appointment', p_patient_id;
    END IF;

    IF v_current_balance < p_copay_amount THEN
        RAISE EXCEPTION 'Insufficient HSA balance: have %, need %',
            v_current_balance, p_copay_amount;
    END IF;

    -- Deduct balance (fires trg_wallet_audit automatically)
    UPDATE patients
    SET hsa_balance = hsa_balance - p_copay_amount
    WHERE id = p_patient_id;

    -- Create the appointment (fails here if idx_active_consult is violated,
    -- rolling back the balance deduction above too)
    INSERT INTO appointments (patient_id, clinic_id, copay_amount, status)
    VALUES (p_patient_id, p_clinic_id, p_copay_amount, 'WAITING');
END;
$$;

