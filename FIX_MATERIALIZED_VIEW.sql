-- ============================================================================
-- FIX: Use MATERIALIZED VIEW for instant queries
-- ============================================================================
-- Materialized views pre-compute the data, so queries are instant.
-- You just need to refresh it periodically (e.g., every hour or on-demand)
-- ============================================================================

-- Drop existing views
DROP VIEW IF EXISTS v_cs_account_health;
DROP VIEW IF EXISTS v_health_score;
DROP MATERIALIZED VIEW IF EXISTS v_cs_account_health;
DROP MATERIALIZED VIEW IF EXISTS v_health_score;

-- ============================================================================
-- Create MATERIALIZED v_health_score
-- ============================================================================
CREATE MATERIALIZED VIEW v_health_score AS
WITH
locations AS (
    SELECT DISTINCT location_id, MAX(dealership_name) as dealership_name
    FROM leads
    WHERE location_id IS NOT NULL
    GROUP BY location_id
),
task_agg AS (
    SELECT
        location_id,
        COUNT(*) as total_tasks,
        SUM(CASE WHEN completed = true THEN 1 ELSE 0 END) as completed_tasks,
        SUM(CASE WHEN completed = false AND due_date < NOW() THEN 1 ELSE 0 END) as overdue_tasks
    FROM tasks
    GROUP BY location_id
),
clarity_agg AS (
    SELECT
        location_id,
        COUNT(*) as total_instructions,
        SUM(CASE WHEN clarity_level = 'complete' THEN 1 ELSE 0 END) as complete_instructions,
        SUM(CASE WHEN clarity_level = 'empty' THEN 1 ELSE 0 END) as empty_instructions,
        SUM(CASE WHEN clarity_level != 'empty' THEN 1 ELSE 0 END) as non_empty_instructions
    FROM v_instruction_clarity
    GROUP BY location_id
),
appt_agg AS (
    SELECT
        location_id,
        SUM(CASE WHEN appointment_time < NOW() THEN 1 ELSE 0 END) as past_appointments,
        SUM(CASE WHEN appointment_time < NOW() AND outcome_status IN ('showed', 'no_show', 'cancelled') THEN 1 ELSE 0 END) as marked_appointments,
        SUM(CASE WHEN appointment_time < NOW() AND outcome_status = 'pending' THEN 1 ELSE 0 END) as unmarked_appointments
    FROM appointments
    GROUP BY location_id
)
SELECT
    l.location_id,
    l.dealership_name,
    COALESCE(t.total_tasks, 0)::int as total_tasks,
    COALESCE(t.completed_tasks, 0)::int as completed_tasks,
    COALESCE(t.overdue_tasks, 0)::int as overdue_tasks,
    CASE
        WHEN COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0) > 0
        THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks), 1)
        ELSE 0
    END::numeric as closed_loop_score,
    COALESCE(c.total_instructions, 0)::int as total_instructions,
    COALESCE(c.complete_instructions, 0)::int as complete_instructions,
    COALESCE(c.empty_instructions, 0)::int as empty_instructions,
    CASE
        WHEN COALESCE(c.non_empty_instructions, 0) > 0
        THEN ROUND(100.0 * c.complete_instructions / c.non_empty_instructions, 1)
        ELSE 0
    END::numeric as clarity_score,
    COALESCE(a.past_appointments, 0)::int as past_appointments,
    COALESCE(a.marked_appointments, 0)::int as marked_appointments,
    COALESCE(a.unmarked_appointments, 0)::int as unmarked_appointments,
    CASE
        WHEN COALESCE(a.past_appointments, 0) > 0
        THEN ROUND(100.0 * a.marked_appointments / a.past_appointments, 1)
        ELSE 0
    END::numeric as marking_score
FROM locations l
LEFT JOIN task_agg t ON l.location_id = t.location_id
LEFT JOIN clarity_agg c ON l.location_id = c.location_id
LEFT JOIN appt_agg a ON l.location_id = a.location_id;

-- Create index for fast lookups
CREATE UNIQUE INDEX idx_health_score_location ON v_health_score(location_id);

-- ============================================================================
-- Create MATERIALIZED v_cs_account_health
-- ============================================================================
CREATE MATERIALIZED VIEW v_cs_account_health AS
WITH health AS (
    SELECT
        *,
        ROUND(closed_loop_score * 0.40 + clarity_score * 0.30 + marking_score * 0.30, 0) as adoption_score
    FROM v_health_score
),
activity_agg AS (
    SELECT
        location_id,
        SUM(CASE WHEN task_created_at >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) as tasks_last_30,
        SUM(CASE WHEN completed = true AND completed_at >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) as completed_last_30,
        MAX(task_created_at) as last_task_created
    FROM tasks
    GROUP BY location_id
),
react_agg AS (
    SELECT
        location_id,
        SUM(CASE WHEN reactivated_at >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) as reactivations_last_30,
        MAX(reactivated_at) as last_reactivation
    FROM reactivations
    GROUP BY location_id
),
appt_activity AS (
    SELECT
        location_id,
        SUM(CASE WHEN appointment_created_at >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) as appointments_last_30,
        MAX(appointment_created_at) as last_appointment_booked,
        SUM(CASE WHEN outcome_status = 'showed' THEN 1 ELSE 0 END) as showed,
        SUM(CASE WHEN outcome_status = 'no_show' THEN 1 ELSE 0 END) as no_shows
    FROM appointments
    GROUP BY location_id
),
lead_agg AS (
    SELECT
        location_id,
        COUNT(*) as total_leads,
        SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active_leads,
        SUM(CASE WHEN lead_date >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) as new_leads_last_30
    FROM leads
    GROUP BY location_id
)
SELECT
    h.location_id,
    h.dealership_name,
    h.adoption_score,
    CASE
        WHEN h.adoption_score >= 80 THEN 'EXCELLENT'
        WHEN h.adoption_score >= 60 THEN 'GOOD'
        WHEN h.adoption_score >= 40 THEN 'FAIR'
        ELSE 'CRITICAL'
    END as health_status,
    h.closed_loop_score,
    h.clarity_score,
    h.marking_score,
    h.total_tasks,
    h.completed_tasks,
    h.overdue_tasks,
    CASE WHEN h.total_tasks > 0 THEN ROUND(100.0 * h.overdue_tasks / h.total_tasks, 1) ELSE 0 END as overdue_pct,
    h.total_instructions,
    h.complete_instructions,
    h.empty_instructions,
    h.past_appointments,
    h.marked_appointments,
    h.unmarked_appointments,
    COALESCE(aa.showed, 0)::int as showed,
    COALESCE(aa.no_shows, 0)::int as no_shows,
    CASE
        WHEN COALESCE(aa.showed, 0) + COALESCE(aa.no_shows, 0) > 0
        THEN ROUND(100.0 * aa.showed / (aa.showed + aa.no_shows), 1)
        ELSE 0
    END as show_rate,
    COALESCE(act.tasks_last_30, 0)::int as tasks_last_30,
    COALESCE(act.completed_last_30, 0)::int as completed_last_30,
    COALESCE(ra.reactivations_last_30, 0)::int as reactivations_last_30,
    COALESCE(aa.appointments_last_30, 0)::int as appointments_last_30,
    act.last_task_created,
    ra.last_reactivation,
    aa.last_appointment_booked,
    LEAST(
        COALESCE(EXTRACT(DAY FROM NOW() - act.last_task_created)::int, 999),
        COALESCE(EXTRACT(DAY FROM NOW() - ra.last_reactivation)::int, 999),
        COALESCE(EXTRACT(DAY FROM NOW() - aa.last_appointment_booked)::int, 999)
    ) as days_since_activity,
    COALESCE(ld.total_leads, 0)::int as total_leads,
    COALESCE(ld.active_leads, 0)::int as active_leads,
    COALESCE(ld.new_leads_last_30, 0)::int as new_leads_last_30,
    CASE
        WHEN COALESCE(ld.new_leads_last_30, 0) > 0
        THEN ROUND(100.0 * (COALESCE(act.tasks_last_30, 0) + COALESCE(aa.appointments_last_30, 0)) / ld.new_leads_last_30, 0)
        ELSE 0
    END as compounding_rate,
    'STABLE'::text as health_trend,
    0::numeric as loop_closure_change,
    CASE
        WHEN h.adoption_score < 40 AND h.overdue_tasks > 20 THEN 'CRITICAL'
        WHEN h.adoption_score < 40 OR h.overdue_tasks > 30 THEN 'AT_RISK'
        WHEN h.adoption_score < 60 OR h.overdue_tasks > 15 OR h.unmarked_appointments > 10 THEN 'NEEDS_ATTENTION'
        WHEN h.adoption_score >= 80 THEN 'EXCELLENT'
        ELSE 'HEALTHY'
    END as risk_level,
    CASE
        WHEN h.closed_loop_score < 50 AND h.overdue_tasks > 10 THEN 'Low loop closure - ' || h.overdue_tasks || ' OVERDUE tasks need attention'
        WHEN h.clarity_score < 30 THEN 'Poor instruction quality - train reps on Context + Action + Timing'
        WHEN h.unmarked_appointments > 5 THEN 'Unmarked appointments - ' || h.unmarked_appointments || ' past appointments need outcomes recorded'
        ELSE 'Account healthy - maintain current performance'
    END as primary_issue,
    0::numeric as pct_from_aged_leads
FROM health h
LEFT JOIN activity_agg act ON h.location_id = act.location_id
LEFT JOIN react_agg ra ON h.location_id = ra.location_id
LEFT JOIN appt_activity aa ON h.location_id = aa.location_id
LEFT JOIN lead_agg ld ON h.location_id = ld.location_id;

-- Create index for fast lookups
CREATE UNIQUE INDEX idx_cs_account_health_location ON v_cs_account_health(location_id);

-- ============================================================================
-- Verify it works (should be instant now!)
-- ============================================================================
SELECT
    COUNT(*) as total_accounts,
    ROUND(AVG(adoption_score), 1) as avg_adoption_score,
    ROUND(AVG(clarity_score), 1) as avg_clarity_score
FROM v_cs_account_health;

-- ============================================================================
-- TO REFRESH DATA (run this periodically or on-demand):
-- ============================================================================
-- REFRESH MATERIALIZED VIEW v_health_score;
-- REFRESH MATERIALIZED VIEW v_cs_account_health;
--
-- You can set up a cron job or Supabase Edge Function to refresh every hour
-- ============================================================================
