-- 06_window_analytics.sql
-- Workflow 2: 7-day moving average of copay revenue per clinic, ranked
-- per-day with DENSE_RANK().

WITH daily_revenue AS (
    SELECT
        clinic_id,
        created_at::date AS day,
        SUM(copay_amount) AS revenue
    FROM appointments
    WHERE created_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY clinic_id, created_at::date
),
moving_avg AS (
    SELECT
        clinic_id,
        day,
        revenue,
        AVG(revenue) OVER (
            PARTITION BY clinic_id
            ORDER BY day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS revenue_7day_avg
    FROM daily_revenue
)
SELECT
    clinic_id,
    day,
    revenue,
    ROUND(revenue_7day_avg, 2) AS revenue_7day_avg,
    DENSE_RANK() OVER (
        PARTITION BY day
        ORDER BY revenue_7day_avg DESC
    ) AS clinic_rank_that_day
FROM moving_avg
ORDER BY day, clinic_rank_that_day;
