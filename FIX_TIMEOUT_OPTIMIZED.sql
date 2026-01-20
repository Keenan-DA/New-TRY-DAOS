-- ============================================================================
-- FIX: Timeout Issue - Optimized Views
-- ============================================================================
-- The previous views were too slow. This version is optimized for performance.
-- ============================================================================

-- Drop existing views
DROP VIEW IF EXISTS v_cs_account_health;
DROP VIEW IF EXISTS v_health_score;

-- ============================================================================
-- OPTIMIZED v_health_score - Simpler, faster
-- ============================================================================
CREATE VIEW v_health_score AS
SELECT
    l.location_id,
    l.dealership_name,

    -- Task metrics (subquery instead of CTE for better optimization)
    COALESCE(t.total_tasks, 0) as total_tasks,
    COALESCE(t.completed_tasks, 0) as completed_tasks,
    COALESCE(t.overdue_tasks, 0) as overdue_tasks,
    COALESCE(t.closed_loop_score, 0) as closed_loop_score,

    -- Clarity metrics
    COALESCE(c.total_instructions, 0) as total_instructions,
    COALESCE(c.complete_instructions, 0) as complete_instructions,
    COALESCE(c.empty_instructions, 0) as empty_instructions,
    COALESCE(c.clarity_score, 0) as clarity_score,

    -- Marking metrics
    COALESCE(m.past_appointments, 0) as past_appointments,
    COALESCE(m.marked_appointments, 0) as marked_appointments,
    COALESCE(m.unmarked_appointments, 0) as unmarked_appointments,
    COALESCE(m.marking_score, 0) as marking_score,

    -- Adoption score
    ROUND(
        COALESCE(t.closed_loop_score, 0) * 0.40 +
        COALESCE(c.clarity_score, 0) * 0.30 +
        COALESCE(m.marking_score, 0) * 0.30
    , 0) as adoption_score,

    -- Health status
    CASE
        WHEN ROUND(COALESCE(t.closed_loop_score, 0) * 0.40 + COALESCE(c.clarity_score, 0) * 0.30 + COALESCE(m.marking_score, 0) * 0.30, 0) >= 80 THEN 'EXCELLENT'
        WHEN ROUND(COALESCE(t.closed_loop_score, 0) * 0.40 + COALESCE(c.clarity_score, 0) * 0.30 + COALESCE(m.marking_score, 0) * 0.30, 0) >= 60 THEN 'GOOD'
        WHEN ROUND(COALESCE(t.closed_loop_score, 0) * 0.40 + COALESCE(c.clarity_score, 0) * 0.30 + COALESCE(m.marking_score, 0) * 0.30, 0) >= 40 THEN 'FAIR'
        ELSE 'CRITICAL'
    END as health_status

FROM (
    -- Get all unique locations with dealership names
    SELECT DISTINCT location_id, dealership_name
    FROM leads
    WHERE location_id IS NOT NULL
) l

LEFT JOIN LATERAL (
    -- Task metrics
    SELECT
        COUNT(*) as total_tasks,
        COUNT(*) FILTER (WHERE completed = true) as completed_tasks,
        COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) as overdue_tasks,
        CASE
            WHEN COUNT(*) FILTER (WHERE completed = true) + COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) > 0
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE completed = true) /
                 (COUNT(*) FILTER (WHERE completed = true) + COUNT(*) FILTER (WHERE completed = false AND due_date < NOW())), 1)
            ELSE 0
        END as closed_loop_score
    FROM tasks
    WHERE tasks.location_id = l.location_id
) t ON true

LEFT JOIN LATERAL (
    -- Clarity metrics from v_instruction_clarity
    SELECT
        COUNT(*) as total_instructions,
        COUNT(*) FILTER (WHERE clarity_level = 'complete') as complete_instructions,
        COUNT(*) FILTER (WHERE clarity_level = 'empty') as empty_instructions,
        CASE
            WHEN COUNT(*) FILTER (WHERE clarity_level != 'empty') > 0
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE clarity_level = 'complete') /
                 COUNT(*) FILTER (WHERE clarity_level != 'empty'), 1)
            ELSE 0
        END as clarity_score
    FROM v_instruction_clarity
    WHERE v_instruction_clarity.location_id = l.location_id
) c ON true

LEFT JOIN LATERAL (
    -- Marking metrics
    SELECT
        COUNT(*) FILTER (WHERE appointment_time < NOW()) as past_appointments,
        COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status IN ('showed', 'no_show', 'cancelled')) as marked_appointments,
        COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status = 'pending') as unmarked_appointments,
        CASE
            WHEN COUNT(*) FILTER (WHERE appointment_time < NOW()) > 0
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status IN ('showed', 'no_show', 'cancelled')) /
                 COUNT(*) FILTER (WHERE appointment_time < NOW()), 1)
            ELSE 0
        END as marking_score
    FROM appointments
    WHERE appointments.location_id = l.location_id
) m ON true;


-- ============================================================================
-- OPTIMIZED v_cs_account_health - Streamlined for dashboard
-- ============================================================================
CREATE VIEW v_cs_account_health AS
SELECT
    h.location_id,
    h.dealership_name,

    -- Health scores
    h.adoption_score,
    h.health_status,
    h.closed_loop_score,
    h.clarity_score,
    h.marking_score,

    -- Task metrics
    h.total_tasks,
    h.completed_tasks,
    h.overdue_tasks,
    CASE WHEN h.total_tasks > 0 THEN ROUND(100.0 * h.overdue_tasks / h.total_tasks, 1) ELSE 0 END as overdue_pct,

    -- Instruction metrics
    h.total_instructions,
    h.complete_instructions,
    h.empty_instructions,

    -- Appointment metrics
    h.past_appointments,
    h.marked_appointments,
    h.unmarked_appointments,

    -- Show/no-show from appointments
    COALESCE(appt.showed, 0) as showed,
    COALESCE(appt.no_shows, 0) as no_shows,
    COALESCE(appt.show_rate, 0) as show_rate,

    -- Activity last 30 days
    COALESCE(act.tasks_last_30, 0) as tasks_last_30,
    COALESCE(act.completed_last_30, 0) as completed_last_30,
    COALESCE(act.reactivations_last_30, 0) as reactivations_last_30,
    COALESCE(act.appointments_last_30, 0) as appointments_last_30,

    -- Timestamps
    act.last_task_created,
    act.last_reactivation,
    act.last_appointment_booked,

    -- Days since activity
    COALESCE(act.days_since_activity, 999) as days_since_activity,

    -- Lead metrics
    COALESCE(ld.total_leads, 0) as total_leads,
    COALESCE(ld.active_leads, 0) as active_leads,
    COALESCE(ld.new_leads_last_30, 0) as new_leads_last_30,

    -- Compounding rate
    CASE
        WHEN COALESCE(ld.new_leads_last_30, 0) > 0
        THEN ROUND(100.0 * (COALESCE(act.tasks_last_30, 0) + COALESCE(act.appointments_last_30, 0)) / ld.new_leads_last_30, 0)
        ELSE 0
    END as compounding_rate,

    -- Placeholders for trend
    'STABLE'::text as health_trend,
    0::numeric as loop_closure_change,

    -- Risk level
    CASE
        WHEN h.adoption_score < 40 AND h.overdue_tasks > 20 THEN 'CRITICAL'
        WHEN h.adoption_score < 40 OR h.overdue_tasks > 30 THEN 'AT_RISK'
        WHEN h.adoption_score < 60 OR h.overdue_tasks > 15 OR h.unmarked_appointments > 10 THEN 'NEEDS_ATTENTION'
        WHEN h.adoption_score >= 80 THEN 'EXCELLENT'
        ELSE 'HEALTHY'
    END as risk_level,

    -- Primary issue
    CASE
        WHEN h.closed_loop_score < 50 AND h.overdue_tasks > 10 THEN 'Low loop closure - ' || h.overdue_tasks || ' OVERDUE tasks need attention'
        WHEN h.clarity_score < 30 THEN 'Poor instruction quality - train reps on Context + Action + Timing'
        WHEN h.unmarked_appointments > 5 THEN 'Unmarked appointments - ' || h.unmarked_appointments || ' past appointments need outcomes recorded'
        ELSE 'Account healthy - maintain current performance'
    END as primary_issue,

    0::numeric as pct_from_aged_leads

FROM v_health_score h

LEFT JOIN LATERAL (
    -- Appointment show/no-show
    SELECT
        COUNT(*) FILTER (WHERE outcome_status = 'showed') as showed,
        COUNT(*) FILTER (WHERE outcome_status = 'no_show') as no_shows,
        CASE
            WHEN COUNT(*) FILTER (WHERE outcome_status IN ('showed', 'no_show')) > 0
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE outcome_status = 'showed') /
                 COUNT(*) FILTER (WHERE outcome_status IN ('showed', 'no_show')), 1)
            ELSE 0
        END as show_rate
    FROM appointments
    WHERE appointments.location_id = h.location_id
) appt ON true

LEFT JOIN LATERAL (
    -- Activity metrics
    SELECT
        (SELECT COUNT(*) FROM tasks WHERE location_id = h.location_id AND task_created_at >= NOW() - INTERVAL '30 days') as tasks_last_30,
        (SELECT COUNT(*) FROM tasks WHERE location_id = h.location_id AND completed = true AND completed_at >= NOW() - INTERVAL '30 days') as completed_last_30,
        (SELECT COUNT(*) FROM reactivations WHERE location_id = h.location_id AND reactivated_at >= NOW() - INTERVAL '30 days') as reactivations_last_30,
        (SELECT COUNT(*) FROM appointments WHERE location_id = h.location_id AND appointment_created_at >= NOW() - INTERVAL '30 days') as appointments_last_30,
        (SELECT MAX(task_created_at) FROM tasks WHERE location_id = h.location_id) as last_task_created,
        (SELECT MAX(reactivated_at) FROM reactivations WHERE location_id = h.location_id) as last_reactivation,
        (SELECT MAX(appointment_created_at) FROM appointments WHERE location_id = h.location_id) as last_appointment_booked,
        GREATEST(
            COALESCE(EXTRACT(DAY FROM NOW() - (SELECT MAX(task_created_at) FROM tasks WHERE location_id = h.location_id)), 999),
            COALESCE(EXTRACT(DAY FROM NOW() - (SELECT MAX(reactivated_at) FROM reactivations WHERE location_id = h.location_id)), 999),
            COALESCE(EXTRACT(DAY FROM NOW() - (SELECT MAX(appointment_created_at) FROM appointments WHERE location_id = h.location_id)), 999)
        )::integer as days_since_activity
) act ON true

LEFT JOIN LATERAL (
    -- Lead metrics
    SELECT
        COUNT(*) as total_leads,
        COUNT(*) FILTER (WHERE status = 'active') as active_leads,
        COUNT(*) FILTER (WHERE lead_date >= NOW() - INTERVAL '30 days') as new_leads_last_30
    FROM leads
    WHERE leads.location_id = h.location_id
) ld ON true;


-- Verify it works
SELECT
    COUNT(*) as total_accounts,
    ROUND(AVG(adoption_score), 1) as avg_adoption_score,
    ROUND(AVG(clarity_score), 1) as avg_clarity_score
FROM v_cs_account_health;
