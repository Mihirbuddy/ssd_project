-- 03_triggers_and_audit.sql
-- Logs every change to patients.hsa_balance into wallet_audit_logs

CREATE OR REPLACE FUNCTION log_wallet_balance_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO wallet_audit_logs (patient_id, amount_changed, action_type, balance_after, logged_at)
    VALUES (
        NEW.id,
        NEW.hsa_balance - OLD.hsa_balance,
        CASE WHEN NEW.hsa_balance > OLD.hsa_balance THEN 'CREDIT' ELSE 'DEBIT' END,
        NEW.hsa_balance,
        now()
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Dropped first so this file can be re-run without erroring on an
-- already-existing trigger. Removing a trigger does not delete the audit
-- rows it previously wrote.
DROP TRIGGER IF EXISTS trg_wallet_audit ON patients;

CREATE TRIGGER trg_wallet_audit
AFTER UPDATE ON patients
FOR EACH ROW
WHEN (OLD.hsa_balance IS DISTINCT FROM NEW.hsa_balance)
EXECUTE FUNCTION log_wallet_balance_change();




