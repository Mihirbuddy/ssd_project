-- 05_materialized_views.sql
-- Aggregates clinics by total monthly patient discharges, with concurrent
-- refresh support.

CREATE MATERIALIZED VIEW clinic_monthly_discharges AS
SELECT
    c.id                                    AS clinic_id,
    c.name                                  AS clinic_name,
    date_trunc('month', a.created_at)::date AS month,
    COUNT(*) FILTER (WHERE a.status = 'DISCHARGED') AS total_discharges
FROM clinics c
JOIN appointments a ON a.clinic_id = c.id
GROUP BY c.id, c.name, date_trunc('month', a.created_at);

-- REFRESH CONCURRENTLY requires a unique index on the view itself
CREATE UNIQUE INDEX idx_clinic_monthly_discharges
ON clinic_monthly_discharges (clinic_id, month);

CREATE OR REPLACE FUNCTION refresh_clinic_monthly_discharges()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY clinic_monthly_discharges;
END;
$$ LANGUAGE plpgsql;

-- Usage:
-- SELECT refresh_clinic_monthly_discharges();
