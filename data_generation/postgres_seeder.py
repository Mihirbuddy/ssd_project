"""
postgres_seeder.py
Seeds patients, clinics, wallet_audit_logs and appointments for CareConnect.

Targets (Step 4):
    100,000+ ledger rows in wallet_audit_logs
     50,000+ appointment rows

Appointments are spread across the last 60 days so 06_window_analytics.sql
has enough history for a meaningful 7-day moving average.

RUN ORDER
    This seeder is order-independent with respect to 03/04. It writes to
    wallet_audit_logs directly and only ever INSERTs into patients, never
    UPDATEs -- and trg_wallet_audit fires on UPDATE only. So the trigger
    cannot double-count these rows whether you run:
        01 -> 02 -> seeder -> 03 -> 04    
    or  01 -> 02 -> 03 -> 04 -> seeder

    Each patient's ledger is generated as a running balance and the patient
    row is then inserted with that final balance, so
        SUM(amount_changed) == patients.hsa_balance
    holds for every patient. See the reconciliation query at the bottom.

Usage:
    pip install -r requirements.txt
    python postgres_seeder.py --dsn "postgresql://user:pass@localhost:5432/careconnect" --truncate
"""
#%%
import os
from dotenv import load_dotenv

load_dotenv()

#%%
import argparse
import random
from datetime import datetime, timedelta
#%%
import psycopg2
from psycopg2.extras import execute_values
from faker import Faker

#%%
fake = Faker()

# Both generators are seeded so a re-run reproduces the same dataset.
random.seed(42)
Faker.seed(42)

BATCH = 5000          # rows per execute_values round-trip
HISTORY_DAYS = 90     # ledger window
APPT_DAYS = 60        # appointment window (Workflow 2 needs ~60d of history)


#%%
# ---------------------------------------------------------------------
# Truncate
# ---------------------------------------------------------------------
def truncate(cur):
    # CASCADE handles the FK order; RESTART IDENTITY is a no-op for UUID
    # PKs but is harmless and keeps this correct if the schema ever moves
    # to serial ids.
    cur.execute("""
        TRUNCATE appointments, wallet_audit_logs, clinics, patients
        RESTART IDENTITY CASCADE
    """)

#%%
# ---------------------------------------------------------------------
# Ledger generation
# ---------------------------------------------------------------------
def build_ledger_for_patient(n_txns, start_time, drain_to_low=False):
    """
    Build one patient's transaction chain as a running balance.

    Returns (rows, final_balance) where rows is a list of
    (amount_changed, action_type, balance_after, logged_at).

    Constraints respected:
      - chk_amount_sign_matches_type: CREDIT > 0, DEBIT < 0, never 0
      - balance_after >= 0.00
      - patients.hsa_balance >= 0.00 (final balance is the last balance_after)
    """
    rows = []
    balance = 0.0
    t = start_time

    # Opening deposit, always a CREDIT so the chain starts above zero.
    opening = round(random.uniform(500, 3000), 2)
    balance = round(balance + opening, 2)
    rows.append((opening, "CREDIT", balance, t))

    for _ in range(n_txns - 1):
        # Advance the clock so logged_at is monotonic per patient -- this is
        # what makes idx_wallet_audit_patient (patient_id, logged_at DESC)
        # meaningful.
        t = t + timedelta(minutes=random.randint(5, 600))

        # Debit only when there is something to spend, else credit.
        if balance > 20 and random.random() < 0.65:
            cap = min(balance, 250.0)
            amount = round(random.uniform(5, cap), 2)
            amount = max(0.01, min(amount, balance))   # never overdraw, never 0
            balance = round(balance - amount, 2)
            rows.append((-amount, "DEBIT", balance, t))
        else:
            amount = round(random.uniform(10, 400), 2)
            amount = max(0.01, amount)                 # never 0
            balance = round(balance + amount, 2)
            rows.append((amount, "CREDIT", balance, t))

    # A slice of patients is drained to a near-zero balance so the
    # "insufficient HSA balance" branch of book_appointment is actually
    # reachable in the seeded data. Without this every patient ends up
    # with hundreds in the wallet and that rejection path is untestable.
    if drain_to_low and balance > 1.0:
        t = t + timedelta(minutes=random.randint(5, 600))
        target = round(random.uniform(0.50, 8.00), 2)
        amount = round(balance - target, 2)
        if amount > 0:
            balance = round(balance - amount, 2)
            rows.append((-amount, "DEBIT", balance, t))

    return rows, balance

#%%
# ---------------------------------------------------------------------
# Seed
# ---------------------------------------------------------------------
def seed(dsn, n_patients, n_clinics, n_appointments, n_ledger, do_truncate):
    conn = psycopg2.connect(dsn)
    cur = conn.cursor()

    if do_truncate:
        truncate(cur)
        conn.commit()
        print("Truncated existing data.")

    # -----------------------------------------------------------------
    # 1. Patients + their ledgers
    # -----------------------------------------------------------------
    # The ledger is built first so each patient can be inserted with the
    # balance their transaction chain actually produces.
    txns_per_patient = max(2, n_ledger // n_patients)
    now = datetime.now()

    # ~5% of patients are drained to a near-zero balance so the
    # insufficient-funds rejection path is testable against seeded data.
    n_low = max(1, n_patients // 20)
    low_balance_slots = set(random.sample(range(n_patients), n_low))

    patient_rows = []     # (name, final_balance)
    ledgers = []          # list of per-patient row lists, index-aligned
    for i in range(n_patients):
        start = now - timedelta(days=random.randint(HISTORY_DAYS - 20, HISTORY_DAYS))
        rows, final_balance = build_ledger_for_patient(
            txns_per_patient, start, drain_to_low=(i in low_balance_slots)
        )
        patient_rows.append((fake.name(), final_balance))
        ledgers.append(rows)

    patient_ids = []
    for i in range(0, len(patient_rows), BATCH):
        chunk = patient_rows[i:i + BATCH]
        ids = execute_values(
            cur,
            "INSERT INTO patients (name, hsa_balance) VALUES %s RETURNING id",
            chunk,
            fetch=True,
        )
        patient_ids.extend(pid[0] for pid in ids)
    conn.commit()
    print(f"Inserted {len(patient_ids)} patients.")

    # Flatten the ledgers now that patient ids exist.
    ledger_rows = []
    for pid, rows in zip(patient_ids, ledgers):
        for amount, action, after, ts in rows:
            ledger_rows.append((pid, amount, action, after, ts))

    inserted_ledger = 0
    for i in range(0, len(ledger_rows), BATCH):
        chunk = ledger_rows[i:i + BATCH]
        execute_values(
            cur,
            """INSERT INTO wallet_audit_logs
               (patient_id, amount_changed, action_type, balance_after, logged_at)
               VALUES %s""",
            chunk,
        )
        inserted_ledger += len(chunk)
        conn.commit()
    print(f"Inserted {inserted_ledger} wallet_audit_logs rows.")

    # -----------------------------------------------------------------
    # 2. Clinics
    # -----------------------------------------------------------------
    clinic_rows = [
        (
            fake.company() + " Clinic",
            float(fake.latitude()),
            float(fake.longitude()),
            random.random() > 0.1,          # ~10% closed to new patients
        )
        for _ in range(n_clinics)
    ]
    # Force at least two closed clinics. At n_clinics=25 the 10% chance
    # above can easily produce zero, which would leave the "clinic is not
    # accepting patients" rejection path untestable.
    closed_slots = random.sample(range(n_clinics), min(2, n_clinics))
    for slot in closed_slots:
        name, lat, lng, _ = clinic_rows[slot]
        clinic_rows[slot] = (name, lat, lng, False)
    clinic_ids = [
        r[0]
        for r in execute_values(
            cur,
            """INSERT INTO clinics (name, latitude, longitude, is_accepting_patients)
               VALUES %s RETURNING id""",
            clinic_rows,
            fetch=True,
        )
    ]
    conn.commit()
    print(f"Inserted {len(clinic_ids)} clinics.")

    # -----------------------------------------------------------------
    # 3. Appointments
    # -----------------------------------------------------------------
    # idx_active_consult allows at most ONE active (WAITING /
    # IN_CONSULTATION) appointment per patient. Rather than inserting
    # randomly and discarding the collisions -- which silently lands you
    # short of the 50k target -- pick a distinct set of patients up front
    # and give each exactly one active row. Everything else is DISCHARGED,
    # which the partial index ignores entirely.
    # Cap at a TENTH of the patient pool, not the whole pool. Capping at
    # n_patients would give every single patient an active appointment,
    # leaving nobody bookable and making book_appointment impossible to
    # demo. This leaves ~90% of patients free.
    n_active = min(int(n_appointments * 0.05), max(1, n_patients // 10))

    # Drained (near-zero balance) patients are kept OUT of the active set,
    # so they stay bookable and can be used to demo the insufficient-funds
    # rejection rather than tripping the double-booking rule first.
    low_ids = {patient_ids[i] for i in low_balance_slots}
    eligible_for_active = [pid for pid in patient_ids if pid not in low_ids]
    n_active = min(n_active, len(eligible_for_active))
    active_patients = set(random.sample(eligible_for_active, n_active))

    appt_rows = []
    for pid in active_patients:
        appt_rows.append((
            pid,
            random.choice(clinic_ids),
            round(random.uniform(10, 150), 2),
            random.choice(["WAITING", "IN_CONSULTATION"]),
            now - timedelta(hours=random.randint(0, 47)),   # active = recent
        ))

    for _ in range(n_appointments - n_active):
        appt_rows.append((
            random.choice(patient_ids),
            random.choice(clinic_ids),
            round(random.uniform(10, 150), 2),
            "DISCHARGED",
            now - timedelta(
                days=random.randint(0, APPT_DAYS),
                hours=random.randint(0, 23),
                minutes=random.randint(0, 59),
            ),
        ))

    random.shuffle(appt_rows)

    inserted_appts = 0
    for i in range(0, len(appt_rows), BATCH):
        chunk = appt_rows[i:i + BATCH]
        execute_values(
            cur,
            """INSERT INTO appointments
               (patient_id, clinic_id, copay_amount, status, created_at)
               VALUES %s""",
            chunk,
        )
        inserted_appts += len(chunk)
        conn.commit()
    print(f"Inserted {inserted_appts} appointments ({n_active} active).")

    # -----------------------------------------------------------------
    # 4. Post-load maintenance
    # -----------------------------------------------------------------
    # Refreshes the planner statistics and the visibility map. Without
    # this the EXPLAIN plans are computed from stale estimates and
    # Index Only Scans will not appear, because freshly-inserted rows are
    # not yet marked all-visible.
    conn.set_session(autocommit=True)
    cur.execute("VACUUM ANALYZE patients;")
    cur.execute("VACUUM ANALYZE wallet_audit_logs;")
    cur.execute("VACUUM ANALYZE clinics;")
    cur.execute("VACUUM ANALYZE appointments;")
    print("VACUUM ANALYZE complete.")

    # -----------------------------------------------------------------
    # 5. Verification
    # -----------------------------------------------------------------
    cur.execute("SELECT count(*) FROM patients;")
    p = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM wallet_audit_logs;")
    w = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM clinics;")
    c = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM appointments;")
    a = cur.fetchone()[0]

    # Ledger must reconcile to the stored balance for every patient.
    cur.execute("""
        SELECT count(*) FROM (
            SELECT p.id
            FROM   patients p
            LEFT   JOIN wallet_audit_logs w ON w.patient_id = p.id
            GROUP  BY p.id, p.hsa_balance
            HAVING p.hsa_balance <> COALESCE(SUM(w.amount_changed), 0)
        ) drift;
    """)
    drift = cur.fetchone()[0]

    # Demo readiness: each of book_appointment's rejection paths needs
    # matching data to exist, or it cannot be demonstrated in the viva.
    cur.execute("""
        SELECT count(*) FROM patients p
        WHERE NOT EXISTS (
            SELECT 1 FROM appointments a
            WHERE a.patient_id = p.id
              AND a.status IN ('WAITING', 'IN_CONSULTATION')
        );
    """)
    free_patients = cur.fetchone()[0]

    cur.execute("SELECT count(*) FROM patients WHERE hsa_balance < 10.00;")
    poor_patients = cur.fetchone()[0]

    cur.execute("SELECT count(*) FROM clinics WHERE is_accepting_patients = false;")
    closed_clinics = cur.fetchone()[0]

    print("\n--- Verification ---")
    print(f"patients          : {p:,}")
    print(f"wallet_audit_logs : {w:,}   (target 100,000+) {'OK' if w >= 100000 else 'SHORT'}")
    print(f"clinics           : {c:,}")
    print(f"appointments      : {a:,}   (target  50,000+) {'OK' if a >= 50000 else 'SHORT'}")
    print(f"ledger drift      : {drift} patients (must be 0)")

    print("\n--- Demo readiness (book_appointment rejection paths) ---")
    print(f"bookable patients      : {free_patients:,}  {'OK' if free_patients > 0 else 'NONE - cannot demo a successful booking'}")
    print(f"low-balance patients   : {poor_patients:,}  {'OK' if poor_patients > 0 else 'NONE - cannot demo insufficient funds'}")
    print(f"closed clinics         : {closed_clinics:,}  {'OK' if closed_clinics > 0 else 'NONE - cannot demo closed clinic'}")
    print(f"patients w/ active appt: {n_active:,}  {'OK' if n_active > 0 else 'NONE - cannot demo double booking'}")

    cur.close()
    conn.close()
#%%

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    # default gets the string from .env if --dsn flag is omitted
    parser.add_argument("--dsn", default=os.getenv("DB_DSN"), help="Postgres connection string")
    parser.add_argument("--patients", type=int, default=2000)
    parser.add_argument("--clinics", type=int, default=25)
    parser.add_argument("--appointments", type=int, default=50000)
    parser.add_argument("--ledger", type=int, default=100000,
                        help="Approximate wallet_audit_logs row target")
    parser.add_argument("--truncate", action="store_true",
                        help="Wipe existing data before seeding")
    args = parser.parse_args()

    if not args.dsn:
        raise ValueError("No DSN provided. Pass --dsn in command line or define DB_DSN in .env file.")

    seed(args.dsn, args.patients, args.clinics,
         args.appointments, args.ledger, args.truncate)
# %%
