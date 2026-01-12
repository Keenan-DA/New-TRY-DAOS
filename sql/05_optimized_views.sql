-- ============================================
-- DA-OS OPTIMIZED VIEWS
-- Run this to replace slow nested views with fast flattened ones
-- ============================================

-- ==========================================
-- STEP 1: Drop problematic views (in dependency order)
-- ==========================================
DROP VIEW IF EXISTS v_cs_account_health CASCADE;
DROP VIEW IF EXISTS v_health_score CASCADE;
DROP VIEW IF EXISTS v_lost_opportunity CASCADE;
DROP VIEW IF EXISTS v_instruction_clarity CASCADE;
DROP VIEW IF EXISTS v_instruction_log CASCADE;

-- ==========================================
-- STEP 2: Create optimized v_dealerships (foundation)
-- ==========================================
CREATE OR REPLACE VIEW v_dealerships AS
SELECT DISTINCT ON (location_id)
    location_id,
    dealership_name,
    dealership_timezone as timezone
FROM (
    SELECT location_id, dealership_name, dealership_timezone FROM tasks WHERE dealership_name IS NOT NULL
    UNION ALL
    SELECT location_id, dealership_name, dealership_timezone FROM leads WHERE dealership_name IS NOT NULL
    UNION ALL
    SELECT location_id, dealership_name, dealership_timezone FROM appointments WHERE dealership_name IS NOT NULL
) combined
WHERE location_id IS NOT NULL
ORDER BY location_id, dealership_name;

-- ==========================================
-- STEP 3: Create simplified v_instruction_clarity (no complex regex)
-- ==========================================
CREATE OR REPLACE VIEW v_instruction_clarity AS
SELECT
    r.id,
    r.location_id,
    r.dealership_name,
    r.contact_id,
    r.lead_name,
    r.assigned_rep_id,
    r.rep_name,
    r.instruction,
    r.instruction_length,
    r.action,
    r.reactivated_at,
    -- Simplified pattern matching (much faster)
    (r.instruction ~* '(interested|wanted|looking|trade|price|vehicle|ready|spoke|mentioned)') AS has_context,
    (r.instruction ~* '(call|text|follow|send|schedule|reach|contact|book)') AS has_action,
    (r.instruction ~* '(today|tomorrow|morning|afternoon|week|asap|soon|next|monday|tuesday|wednesday|thursday|friday)') AS has_timing,
    CASE
        WHEN r.instruction IS NULL OR length(trim(r.instruction)) = 0 THEN 'empty'
        WHEN (r.instruction ~* '(call|text|follow|send|schedule|reach|contact|book)')
         AND (r.instruction ~* '(today|tomorrow|morning|afternoon|week|asap|soon|next)')
         AND (r.instruction ~* '(interested|wanted|looking|trade|price|vehicle|ready|spoke)') THEN 'complete'
        WHEN (r.instruction ~* '(call|text|follow|send|schedule|reach|contact|book)')
          OR (r.instruction ~* '(today|tomorrow|morning|afternoon|week|asap|soon|next)') THEN 'partial'
        ELSE 'incomplete'
    END AS clarity_level,
    r.follow_up_message,
    r.follow_up_date,
    r.appointment_type,
    r.appointment_time
FROM reactivations r
WHERE r.location_id IS NOT NULL;

-- ==========================================
-- STEP 4: Create v_instruction_log (depends on v_instruction_clarity)
-- ==========================================
CREATE OR REPLACE VIEW v_instruction_log AS
SELECT
    id,
    location_id,
    dealership_name,
    contact_id,
    lead_name,
    assigned_rep_id,
    rep_name,
    instruction,
    action,
    clarity_level,
    has_context,
    has_action,
    has_timing,
    follow_up_message,
    follow_up_date,
    appointment_type,
    appointment_time,
    reactivated_at,
    CASE action
        WHEN 'follow_up' THEN 'Follow-up'
        WHEN 'appointment' THEN 'Appointment'
        WHEN 'remove' THEN 'Remove'
        ELSE action
    END AS action_display,
    CASE clarity_level
        WHEN 'complete' THEN 'Complete'
        WHEN 'partial' THEN 'Partial'
        WHEN 'incomplete' THEN 'Incomplete'
        WHEN 'empty' THEN 'Empty'
        ELSE clarity_level
    END AS clarity_display
FROM v_instruction_clarity;

-- ==========================================
-- STEP 5: Create FLATTENED v_cs_account_health (main view - NO dependencies)
-- ==========================================
CREATE OR REPLACE VIEW v_cs_account_health AS
WITH
-- Get dealership names
dealerships AS (
    SELECT DISTINCT ON (location_id)
        location_id,
        dealership_name
    FROM tasks
    WHERE dealership_name IS NOT NULL
    ORDER BY location_id, created_at DESC
),

-- Task metrics per location
task_metrics AS (
    SELECT
        location_id,
        COUNT(*) AS total_tasks,
        COUNT(*) FILTER (WHERE completed = true) AS completed_tasks,
        COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) AS overdue_tasks,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS tasks_last_30,
        MAX(created_at) AS last_task_created
    FROM tasks
    GROUP BY location_id
),

-- Reactivation metrics per location (simplified clarity calculation)
reactivation_metrics AS (
    SELECT
        location_id,
        COUNT(*) FILTER (WHERE reactivated_at >= NOW() - INTERVAL '30 days') AS reactivations_last_30,
        MAX(reactivated_at) AS last_reactivation,
        -- Simplified clarity score
        ROUND(100.0 * COUNT(*) FILTER (WHERE
            instruction IS NOT NULL
            AND length(trim(instruction)) > 0
            AND instruction ~* '(call|text|follow|send|schedule|reach|contact|book)'
            AND instruction ~* '(today|tomorrow|morning|afternoon|week|asap|soon|next)'
            AND instruction ~* '(interested|wanted|looking|trade|price|vehicle|ready|spoke)'
        ) / NULLIF(COUNT(*) FILTER (WHERE instruction IS NOT NULL AND length(trim(instruction)) > 0), 0), 1) AS clarity_score
    FROM reactivations
    GROUP BY location_id
),

-- Appointment metrics per location
appointment_metrics AS (
    SELECT
        location_id,
        COUNT(*) FILTER (WHERE appointment_created_at >= NOW() - INTERVAL '30 days') AS appointments_last_30,
        COUNT(*) FILTER (WHERE appointment_time < NOW()) AS past_appointments,
        COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status != 'pending') AS marked_appointments,
        COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status = 'pending') AS unmarked_appointments,
        COUNT(*) FILTER (WHERE outcome_status = 'showed') AS showed,
        COUNT(*) FILTER (WHERE outcome_status = 'no_show') AS no_shows,
        MAX(appointment_created_at) AS last_appointment_booked
    FROM appointments
    GROUP BY location_id
),

-- Lead metrics per location
lead_metrics AS (
    SELECT
        location_id,
        COUNT(*) AS total_leads,
        COUNT(*) FILTER (WHERE status = 'active') AS active_leads,
        COUNT(*) FILTER (WHERE lead_date >= NOW() - INTERVAL '30 days') AS new_leads_last_30
    FROM leads
    GROUP BY location_id
)

-- Main SELECT - combine all metrics
SELECT
    d.location_id,
    d.dealership_name,

    -- Calculate adoption score components
    COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) AS closed_loop_score,
    COALESCE(rm.clarity_score, 0) AS clarity_score,
    COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) AS marking_score,

    -- Calculate adoption score (weighted average)
    ROUND(
        (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
        (COALESCE(rm.clarity_score, 0) * 0.30) +
        (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
    , 0) AS adoption_score,

    -- Health status based on adoption score
    CASE
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) >= 80 THEN 'EXCELLENT'
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) >= 60 THEN 'GOOD'
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) >= 40 THEN 'FAIR'
        ELSE 'CRITICAL'
    END AS health_status,

    -- Compounding rate
    ROUND(100.0 * (COALESCE(tm.tasks_last_30, 0) + COALESCE(am.appointments_last_30, 0)) / NULLIF(lm.new_leads_last_30, 0), 1) AS compounding_rate,

    -- Task metrics
    COALESCE(tm.total_tasks, 0) AS total_tasks,
    COALESCE(tm.completed_tasks, 0) AS completed_tasks,
    COALESCE(tm.overdue_tasks, 0) AS overdue_tasks,
    COALESCE(tm.tasks_last_30, 0) AS tasks_last_30,

    -- Reactivation metrics
    COALESCE(rm.reactivations_last_30, 0) AS reactivations_last_30,

    -- Appointment metrics
    COALESCE(am.appointments_last_30, 0) AS appointments_last_30,
    COALESCE(am.past_appointments, 0) AS past_appointments,
    COALESCE(am.showed, 0) AS showed,
    COALESCE(am.no_shows, 0) AS no_shows,
    COALESCE(am.unmarked_appointments, 0) AS unmarked_appointments,
    ROUND(100.0 * am.showed / NULLIF(am.showed + am.no_shows, 0), 1) AS show_rate,

    -- Lead metrics
    COALESCE(lm.total_leads, 0) AS total_leads,
    COALESCE(lm.active_leads, 0) AS active_leads,
    COALESCE(lm.new_leads_last_30, 0) AS new_leads_last_30,

    -- Activity tracking
    GREATEST(
        COALESCE(tm.last_task_created, '1970-01-01'::timestamptz),
        COALESCE(rm.last_reactivation, '1970-01-01'::timestamptz),
        COALESCE(am.last_appointment_booked, '1970-01-01'::timestamptz)
    ) AS last_activity,
    EXTRACT(DAY FROM NOW() - GREATEST(
        COALESCE(tm.last_task_created, '1970-01-01'::timestamptz),
        COALESCE(rm.last_reactivation, '1970-01-01'::timestamptz),
        COALESCE(am.last_appointment_booked, '1970-01-01'::timestamptz)
    ))::integer AS days_since_activity,

    -- Trend (simplified - always STABLE for now, can be enhanced later)
    'STABLE' AS health_trend,

    -- Risk level
    CASE
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) < 40 AND COALESCE(tm.overdue_tasks, 0) > 20 THEN 'CRITICAL'
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) < 40 OR COALESCE(tm.overdue_tasks, 0) > 30 THEN 'AT_RISK'
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) < 60 OR COALESCE(tm.overdue_tasks, 0) > 15 OR COALESCE(am.unmarked_appointments, 0) > 10 THEN 'NEEDS_ATTENTION'
        WHEN ROUND(
            (COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) * 0.40) +
            (COALESCE(rm.clarity_score, 0) * 0.30) +
            (COALESCE(ROUND(100.0 * am.marked_appointments / NULLIF(am.past_appointments, 0), 1), 0) * 0.30)
        , 0) >= 80 THEN 'EXCELLENT'
        ELSE 'HEALTHY'
    END AS risk_level,

    -- Primary issue
    CASE
        WHEN COALESCE(ROUND(100.0 * tm.completed_tasks / NULLIF(tm.completed_tasks + tm.overdue_tasks, 0), 1), 0) < 50 AND COALESCE(tm.overdue_tasks, 0) > 0
            THEN 'Low loop closure - ' || COALESCE(tm.overdue_tasks, 0) || ' OVERDUE tasks need attention'
        WHEN COALESCE(rm.clarity_score, 0) < 50
            THEN 'Poor instruction quality - train reps on Context + Action + Timing'
        WHEN COALESCE(am.unmarked_appointments, 0) > 5
            THEN 'Unmarked appointments - ' || COALESCE(am.unmarked_appointments, 0) || ' past appointments need outcomes recorded'
        WHEN ROUND(100.0 * am.showed / NULLIF(am.showed + am.no_shows, 0), 1) < 50
            THEN 'Low show rate - improve confirmation process'
        WHEN ROUND(100.0 * (COALESCE(tm.tasks_last_30, 0) + COALESCE(am.appointments_last_30, 0)) / NULLIF(lm.new_leads_last_30, 0), 1) < 100
            THEN 'Low compounding rate - pipeline not growing, increase adoption'
        ELSE 'Account healthy - maintain current performance'
    END AS primary_issue

FROM dealerships d
LEFT JOIN task_metrics tm ON d.location_id = tm.location_id
LEFT JOIN reactivation_metrics rm ON d.location_id = rm.location_id
LEFT JOIN appointment_metrics am ON d.location_id = am.location_id
LEFT JOIN lead_metrics lm ON d.location_id = lm.location_id;

-- ==========================================
-- STEP 6: Create optimized v_lost_opportunity
-- ==========================================
CREATE OR REPLACE VIEW v_lost_opportunity AS
WITH
dealerships AS (
    SELECT DISTINCT ON (location_id)
        location_id,
        dealership_name
    FROM tasks
    WHERE dealership_name IS NOT NULL
    ORDER BY location_id, created_at DESC
),
task_stats AS (
    SELECT
        location_id,
        COUNT(*) AS total_tasks,
        COUNT(*) FILTER (WHERE completed = true) AS completed_tasks,
        COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) AS overdue_tasks
    FROM tasks
    GROUP BY location_id
),
instruction_stats AS (
    SELECT
        location_id,
        COUNT(*) AS total_reactivations,
        COUNT(*) FILTER (WHERE instruction IS NOT NULL AND length(trim(instruction)) > 0
            AND instruction ~* '(call|text|follow|send|schedule|reach|contact|book)'
            AND instruction ~* '(today|tomorrow|morning|afternoon|week|asap|soon|next)'
            AND instruction ~* '(interested|wanted|looking|trade|price|vehicle|ready|spoke)') AS complete_instructions,
        COUNT(*) FILTER (WHERE instruction IS NULL OR length(trim(instruction)) = 0) AS empty_instructions,
        COUNT(*) FILTER (WHERE instruction IS NOT NULL AND length(trim(instruction)) > 0
            AND NOT (instruction ~* '(call|text|follow|send|schedule|reach|contact|book)'
                AND instruction ~* '(today|tomorrow|morning|afternoon|week|asap|soon|next)'
                AND instruction ~* '(interested|wanted|looking|trade|price|vehicle|ready|spoke)')) AS incomplete_instructions,
        COUNT(*) FILTER (WHERE action = 'remove') AS rep_remove_count
    FROM reactivations
    GROUP BY location_id
),
unmarked_stats AS (
    SELECT
        location_id,
        COUNT(*) AS unmarked_appointments
    FROM appointments
    WHERE outcome_status = 'pending' AND appointment_time < NOW()
    GROUP BY location_id
),
appt_conversion AS (
    SELECT
        t.location_id,
        COUNT(DISTINCT a.id)::numeric / NULLIF(COUNT(DISTINCT t.id) FILTER (WHERE t.completed = true), 0)::numeric AS appt_per_completed_task
    FROM tasks t
    LEFT JOIN appointments a ON t.location_id = a.location_id
    GROUP BY t.location_id
)
SELECT
    d.location_id,
    d.dealership_name,
    COALESCE(ac.appt_per_completed_task, 0) AS appt_per_completed_task,
    COALESCE(ts.completed_tasks, 0) AS completed_tasks_all_time,
    COALESCE(ts.overdue_tasks, 0) AS overdue_tasks,
    ROUND(COALESCE(ts.overdue_tasks, 0)::numeric * COALESCE(ac.appt_per_completed_task, 0), 1) AS est_lost_from_overdue,
    COALESCE(ins.empty_instructions, 0) AS empty_instructions,
    COALESCE(ins.incomplete_instructions, 0) AS incomplete_instructions,
    ROUND((COALESCE(ins.empty_instructions, 0)::numeric * COALESCE(ac.appt_per_completed_task, 0)) +
          (COALESCE(ins.incomplete_instructions, 0)::numeric * COALESCE(ac.appt_per_completed_task, 0) * 0.3), 1) AS est_lost_from_poor_instructions,
    COALESCE(um.unmarked_appointments, 0) AS unmarked_appointments,
    COALESCE(ins.rep_remove_count, 0) AS rep_removals,
    COALESCE(ts.total_tasks, 0) AS total_tasks,
    COALESCE(ins.total_reactivations, 0) AS total_reactivations,
    COALESCE(ins.complete_instructions, 0) AS complete_instructions
FROM dealerships d
LEFT JOIN task_stats ts ON d.location_id = ts.location_id
LEFT JOIN instruction_stats ins ON d.location_id = ins.location_id
LEFT JOIN unmarked_stats um ON d.location_id = um.location_id
LEFT JOIN appt_conversion ac ON d.location_id = ac.location_id;

-- ==========================================
-- STEP 7: Verify the views work
-- ==========================================
-- Test queries (run these to verify)
-- SELECT COUNT(*) FROM v_cs_account_health;
-- SELECT * FROM v_cs_account_health LIMIT 3;
-- SELECT COUNT(*) FROM v_lost_opportunity;
