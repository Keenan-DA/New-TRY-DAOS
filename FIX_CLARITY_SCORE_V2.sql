-- ============================================================================
-- FIX: Clarity Score Calculation - FULL SCRIPT v2
-- ============================================================================
-- Run this entire script in Supabase SQL Editor
-- ============================================================================

-- Step 1: Drop all dependent views first (in correct order)
DROP VIEW IF EXISTS v_cs_account_health;
DROP VIEW IF EXISTS v_health_trend;
DROP VIEW IF EXISTS v_health_score;

-- Step 2: Recreate v_health_score with CORRECT clarity calculation
CREATE VIEW v_health_score AS
WITH
-- Task metrics per location
task_metrics AS (
    SELECT
        location_id,
        COUNT(*) as total_tasks,
        COUNT(*) FILTER (WHERE completed = true) as completed_tasks,
        COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) as overdue_tasks
    FROM tasks
    GROUP BY location_id
),

-- Instruction clarity metrics per location (THE FIX IS HERE)
clarity_metrics AS (
    SELECT
        location_id,
        COUNT(*) as total_instructions,
        COUNT(*) FILTER (WHERE clarity_level = 'complete') as complete_instructions,
        COUNT(*) FILTER (WHERE clarity_level = 'empty') as empty_instructions,
        COUNT(*) FILTER (WHERE clarity_level != 'empty') as non_empty_instructions
    FROM v_instruction_clarity
    GROUP BY location_id
),

-- Appointment marking metrics per location
marking_metrics AS (
    SELECT
        location_id,
        COUNT(*) FILTER (WHERE appointment_time < NOW()) as past_appointments,
        COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status IN ('showed', 'no_show', 'cancelled')) as marked_appointments,
        COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status = 'pending') as unmarked_appointments
    FROM appointments
    GROUP BY location_id
),

-- Get dealership names
dealerships AS (
    SELECT DISTINCT location_id, dealership_name
    FROM leads
    WHERE dealership_name IS NOT NULL
)

SELECT
    COALESCE(t.location_id, c.location_id, m.location_id) as location_id,
    d.dealership_name,

    -- Task metrics
    COALESCE(t.total_tasks, 0) as total_tasks,
    COALESCE(t.completed_tasks, 0) as completed_tasks,
    COALESCE(t.overdue_tasks, 0) as overdue_tasks,

    -- Loop closure score: completed / (completed + overdue) * 100
    CASE
        WHEN COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0) > 0
        THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks), 1)
        ELSE 0
    END as closed_loop_score,

    -- Instruction metrics
    COALESCE(c.total_instructions, 0) as total_instructions,
    COALESCE(c.complete_instructions, 0) as complete_instructions,
    COALESCE(c.empty_instructions, 0) as empty_instructions,

    -- FIXED: Clarity score = complete / non-empty * 100
    CASE
        WHEN COALESCE(c.non_empty_instructions, 0) > 0
        THEN ROUND(100.0 * c.complete_instructions / c.non_empty_instructions, 1)
        ELSE 0
    END as clarity_score,

    -- Appointment metrics
    COALESCE(m.past_appointments, 0) as past_appointments,
    COALESCE(m.marked_appointments, 0) as marked_appointments,
    COALESCE(m.unmarked_appointments, 0) as unmarked_appointments,

    -- Marking score: marked / past * 100
    CASE
        WHEN COALESCE(m.past_appointments, 0) > 0
        THEN ROUND(100.0 * m.marked_appointments / m.past_appointments, 1)
        ELSE 0
    END as marking_score,

    -- ADOPTION SCORE: (loop * 0.4) + (clarity * 0.3) + (marking * 0.3)
    ROUND(
        (CASE
            WHEN COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0) > 0
            THEN 100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks)
            ELSE 0
        END * 0.40) +
        (CASE
            WHEN COALESCE(c.non_empty_instructions, 0) > 0
            THEN 100.0 * c.complete_instructions / c.non_empty_instructions
            ELSE 0
        END * 0.30) +
        (CASE
            WHEN COALESCE(m.past_appointments, 0) > 0
            THEN 100.0 * m.marked_appointments / m.past_appointments
            ELSE 0
        END * 0.30)
    , 0) as adoption_score,

    -- Health status based on adoption score
    CASE
        WHEN ROUND(
            (CASE WHEN COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0) > 0
                  THEN 100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) ELSE 0 END * 0.40) +
            (CASE WHEN COALESCE(c.non_empty_instructions, 0) > 0
                  THEN 100.0 * c.complete_instructions / c.non_empty_instructions ELSE 0 END * 0.30) +
            (CASE WHEN COALESCE(m.past_appointments, 0) > 0
                  THEN 100.0 * m.marked_appointments / m.past_appointments ELSE 0 END * 0.30)
        , 0) >= 80 THEN 'EXCELLENT'
        WHEN ROUND(
            (CASE WHEN COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0) > 0
                  THEN 100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) ELSE 0 END * 0.40) +
            (CASE WHEN COALESCE(c.non_empty_instructions, 0) > 0
                  THEN 100.0 * c.complete_instructions / c.non_empty_instructions ELSE 0 END * 0.30) +
            (CASE WHEN COALESCE(m.past_appointments, 0) > 0
                  THEN 100.0 * m.marked_appointments / m.past_appointments ELSE 0 END * 0.30)
        , 0) >= 60 THEN 'GOOD'
        WHEN ROUND(
            (CASE WHEN COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0) > 0
                  THEN 100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) ELSE 0 END * 0.40) +
            (CASE WHEN COALESCE(c.non_empty_instructions, 0) > 0
                  THEN 100.0 * c.complete_instructions / c.non_empty_instructions ELSE 0 END * 0.30) +
            (CASE WHEN COALESCE(m.past_appointments, 0) > 0
                  THEN 100.0 * m.marked_appointments / m.past_appointments ELSE 0 END * 0.30)
        , 0) >= 40 THEN 'FAIR'
        ELSE 'CRITICAL'
    END as health_status

FROM task_metrics t
FULL OUTER JOIN clarity_metrics c ON t.location_id = c.location_id
FULL OUTER JOIN marking_metrics m ON COALESCE(t.location_id, c.location_id) = m.location_id
LEFT JOIN dealerships d ON COALESCE(t.location_id, c.location_id, m.location_id) = d.location_id;

-- Step 3: Recreate v_cs_account_health
CREATE VIEW v_cs_account_health AS
WITH
-- Base health score
health AS (
    SELECT * FROM v_health_score
),

-- Activity metrics (last 30 days)
activity AS (
    SELECT
        location_id,
        COUNT(*) FILTER (WHERE task_created_at >= NOW() - INTERVAL '30 days') as tasks_last_30,
        COUNT(*) FILTER (WHERE completed = true AND completed_at >= NOW() - INTERVAL '30 days') as completed_last_30,
        MAX(task_created_at) as last_task_created
    FROM tasks
    GROUP BY location_id
),

reactivation_activity AS (
    SELECT
        location_id,
        COUNT(*) FILTER (WHERE reactivated_at >= NOW() - INTERVAL '30 days') as reactivations_last_30,
        MAX(reactivated_at) as last_reactivation
    FROM reactivations
    GROUP BY location_id
),

appointment_activity AS (
    SELECT
        location_id,
        COUNT(*) FILTER (WHERE appointment_created_at >= NOW() - INTERVAL '30 days') as appointments_last_30,
        MAX(appointment_created_at) as last_appointment_booked,
        COUNT(*) FILTER (WHERE outcome_status = 'showed') as showed,
        COUNT(*) FILTER (WHERE outcome_status = 'no_show') as no_shows
    FROM appointments
    GROUP BY location_id
),

-- Lead metrics
lead_metrics AS (
    SELECT
        location_id,
        COUNT(*) as total_leads,
        COUNT(*) FILTER (WHERE status = 'active') as active_leads,
        COUNT(*) FILTER (WHERE lead_date >= NOW() - INTERVAL '30 days') as new_leads_last_30
    FROM leads
    GROUP BY location_id
),

-- Compounding rate calculation
compounding AS (
    SELECT
        h.location_id,
        COALESCE(a.tasks_last_30, 0) + COALESCE(aa.appointments_last_30, 0) as actions_last_30,
        COALESCE(l.new_leads_last_30, 0) as new_leads_last_30,
        CASE
            WHEN COALESCE(l.new_leads_last_30, 0) > 0
            THEN ROUND(100.0 * (COALESCE(a.tasks_last_30, 0) + COALESCE(aa.appointments_last_30, 0)) / l.new_leads_last_30, 0)
            ELSE 0
        END as compounding_rate
    FROM v_health_score h
    LEFT JOIN activity a ON h.location_id = a.location_id
    LEFT JOIN appointment_activity aa ON h.location_id = aa.location_id
    LEFT JOIN lead_metrics l ON h.location_id = l.location_id
)

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
    CASE
        WHEN h.total_tasks > 0
        THEN ROUND(100.0 * h.overdue_tasks / h.total_tasks, 1)
        ELSE 0
    END as overdue_pct,

    -- Instruction metrics
    h.total_instructions,
    h.complete_instructions,
    h.empty_instructions,

    -- Appointment metrics
    h.past_appointments,
    h.marked_appointments,
    h.unmarked_appointments,
    COALESCE(aa.showed, 0) as showed,
    COALESCE(aa.no_shows, 0) as no_shows,
    CASE
        WHEN COALESCE(aa.showed, 0) + COALESCE(aa.no_shows, 0) > 0
        THEN ROUND(100.0 * aa.showed / (aa.showed + aa.no_shows), 1)
        ELSE 0
    END as show_rate,

    -- Activity (last 30 days)
    COALESCE(a.tasks_last_30, 0) as tasks_last_30,
    COALESCE(a.completed_last_30, 0) as completed_last_30,
    COALESCE(ra.reactivations_last_30, 0) as reactivations_last_30,
    COALESCE(aa.appointments_last_30, 0) as appointments_last_30,

    -- Last activity timestamps
    a.last_task_created,
    ra.last_reactivation,
    aa.last_appointment_booked,

    -- Days since activity
    GREATEST(
        COALESCE(EXTRACT(DAY FROM NOW() - a.last_task_created), 999),
        COALESCE(EXTRACT(DAY FROM NOW() - ra.last_reactivation), 999),
        COALESCE(EXTRACT(DAY FROM NOW() - aa.last_appointment_booked), 999)
    )::integer as days_since_activity,

    -- Lead metrics
    COALESCE(l.total_leads, 0) as total_leads,
    COALESCE(l.active_leads, 0) as active_leads,
    COALESCE(l.new_leads_last_30, 0) as new_leads_last_30,

    -- Compounding rate (North Star)
    COALESCE(c.compounding_rate, 0) as compounding_rate,

    -- Health trend placeholder
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

    -- Primary issue identification
    CASE
        WHEN h.closed_loop_score < 50 AND h.overdue_tasks > 10
            THEN 'Low loop closure - ' || h.overdue_tasks || ' OVERDUE tasks need attention'
        WHEN h.clarity_score < 30
            THEN 'Poor instruction quality - train reps on Context + Action + Timing'
        WHEN h.unmarked_appointments > 5
            THEN 'Unmarked appointments - ' || h.unmarked_appointments || ' past appointments need outcomes recorded'
        WHEN COALESCE(c.compounding_rate, 0) < 80
            THEN 'Low compounding rate - pipeline not growing, increase adoption'
        ELSE 'Account healthy - maintain current performance'
    END as primary_issue,

    -- Aged lead conversion placeholder
    0::numeric as pct_from_aged_leads

FROM health h
LEFT JOIN activity a ON h.location_id = a.location_id
LEFT JOIN reactivation_activity ra ON h.location_id = ra.location_id
LEFT JOIN appointment_activity aa ON h.location_id = aa.location_id
LEFT JOIN lead_metrics l ON h.location_id = l.location_id
LEFT JOIN compounding c ON h.location_id = c.location_id;

-- Step 4: Verify the fix
SELECT
    'AFTER FIX' as status,
    COUNT(*) as total_accounts,
    ROUND(AVG(adoption_score), 1) as avg_adoption_score,
    ROUND(AVG(closed_loop_score), 1) as avg_loop_closure,
    ROUND(AVG(clarity_score), 1) as avg_clarity_score,
    ROUND(AVG(marking_score), 1) as avg_marking_score,
    COUNT(*) FILTER (WHERE health_status = 'EXCELLENT') as excellent_count,
    COUNT(*) FILTER (WHERE health_status = 'GOOD') as good_count,
    COUNT(*) FILTER (WHERE health_status = 'FAIR') as fair_count,
    COUNT(*) FILTER (WHERE health_status = 'CRITICAL') as critical_count
FROM v_cs_account_health;
