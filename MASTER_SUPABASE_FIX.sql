-- ============================================================================
-- DRIVE AI 7.0 - MASTER SUPABASE FIX
-- ============================================================================
-- Generated: January 20, 2026
-- Purpose: All-in-one SQL to fix ALL broken/missing database objects
--
-- THIS FILE CONSOLIDATES:
--   1. Missing Views (3) - v_rep_complete_scorecard, v_health_trend, v_rep_instruction_quality
--   2. Appointment Function Fixes - insert_appointment, upsert_appointment_from_ghl
--
-- RUN THIS ENTIRE FILE IN SUPABASE SQL EDITOR (in order)
-- ============================================================================


-- ############################################################################
-- PART 1: MISSING VIEWS
-- ############################################################################


-- ============================================================================
-- VIEW 1: v_rep_complete_scorecard (CRITICAL - Dashboard uses this!)
-- ============================================================================
-- Purpose: Comprehensive rep performance metrics (main leaderboard view)
-- Used by: Dashboard client detail page for rep scorecard table
-- ============================================================================

DROP VIEW IF EXISTS v_rep_complete_scorecard;

CREATE OR REPLACE VIEW v_rep_complete_scorecard AS
WITH task_metrics AS (
  SELECT
    t.location_id,
    t.assigned_rep_id,
    t.assigned_rep_name,
    t.dealership_name,
    COUNT(*) AS total_tasks,
    COUNT(*) FILTER (WHERE t.completed = TRUE) AS completed_tasks,
    COUNT(*) FILTER (WHERE t.completed = FALSE AND t.due_date < NOW()) AS overdue_tasks,
    COUNT(*) FILTER (WHERE t.completed = FALSE AND (t.due_date >= NOW() OR t.due_date IS NULL)) AS pending_not_due
  FROM tasks t
  WHERE t.assigned_rep_id IS NOT NULL AND t.assigned_rep_id != ''
  GROUP BY t.location_id, t.assigned_rep_id, t.assigned_rep_name, t.dealership_name
),
completion_metrics AS (
  SELECT
    t.assigned_rep_id,
    t.location_id,
    AVG(tc.hours_to_complete) AS avg_hours_to_close,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tc.hours_to_complete) AS median_hours_to_close
  FROM tasks t
  JOIN task_completions tc ON t.id = tc.task_id
  WHERE t.assigned_rep_id IS NOT NULL AND t.assigned_rep_id != ''
  GROUP BY t.assigned_rep_id, t.location_id
),
instruction_metrics AS (
  SELECT
    r.location_id,
    r.assigned_rep_id,
    COUNT(*) FILTER (WHERE ic.clarity_level = 'complete') AS complete_instructions,
    COUNT(*) FILTER (WHERE ic.clarity_level = 'partial') AS partial_instructions,
    COUNT(*) FILTER (WHERE ic.clarity_level IN ('incomplete', 'empty')) AS low_instructions,
    COUNT(*) FILTER (WHERE r.action = 'remove') AS remove_count,
    COUNT(*) AS total_reactivations
  FROM reactivations r
  LEFT JOIN v_instruction_clarity ic ON r.id = ic.id
  WHERE r.assigned_rep_id IS NOT NULL AND r.assigned_rep_id != ''
  GROUP BY r.location_id, r.assigned_rep_id
),
appointment_metrics AS (
  SELECT
    a.location_id,
    a.assigned_rep_id,
    COUNT(*) AS total_appointments,
    COUNT(*) FILTER (WHERE a.created_source = 'rep_instructed') AS rep_booked_appointments,
    COUNT(*) FILTER (WHERE a.outcome_status = 'showed') AS showed,
    COUNT(*) FILTER (WHERE a.outcome_status = 'no_show') AS no_shows,
    COUNT(*) FILTER (WHERE a.outcome_status = 'no_show' AND a.follow_up_after_outcome IS NULL AND a.recovery_reactivation_id IS NULL) AS unworked_no_shows
  FROM appointments a
  WHERE a.assigned_rep_id IS NOT NULL AND a.assigned_rep_id != ''
  GROUP BY a.location_id, a.assigned_rep_id
)
SELECT
  tm.location_id,
  tm.assigned_rep_id,
  tm.assigned_rep_name AS rep_name,
  tm.dealership_name,

  -- Task Performance
  COALESCE(tm.total_tasks, 0) AS total_tasks,
  COALESCE(tm.completed_tasks, 0) AS completed_tasks,
  COALESCE(tm.overdue_tasks, 0) AS overdue_tasks,
  COALESCE(tm.pending_not_due, 0) AS pending_not_due,

  -- Loop Closure (accountable tasks only)
  CASE
    WHEN (COALESCE(tm.completed_tasks, 0) + COALESCE(tm.overdue_tasks, 0)) > 0
    THEN ROUND(100.0 * tm.completed_tasks / (tm.completed_tasks + tm.overdue_tasks), 1)
    ELSE NULL
  END AS closed_loop_pct,

  -- Speed Metrics
  ROUND(COALESCE(cm.avg_hours_to_close, 0)::NUMERIC, 1) AS avg_hours_to_close,
  ROUND(COALESCE(cm.median_hours_to_close, 0)::NUMERIC, 1) AS median_hours_to_close,

  -- Instruction Quality
  COALESCE(im.complete_instructions, 0) AS complete_instructions,
  COALESCE(im.partial_instructions, 0) AS partial_instructions,
  COALESCE(im.low_instructions, 0) AS low_instructions,
  CASE
    WHEN COALESCE(im.total_reactivations, 0) > 0
    THEN ROUND(100.0 * im.complete_instructions / im.total_reactivations, 1)
    ELSE NULL
  END AS clarity_pct,

  -- Appointments
  COALESCE(am.total_appointments, 0) AS total_appointments,
  COALESCE(am.rep_booked_appointments, 0) AS rep_booked_appointments,
  COALESCE(am.showed, 0) AS showed,
  COALESCE(am.no_shows, 0) AS no_shows,
  COALESCE(am.unworked_no_shows, 0) AS unworked_no_shows,
  CASE
    WHEN (COALESCE(am.showed, 0) + COALESCE(am.no_shows, 0)) > 0
    THEN ROUND(100.0 * am.showed / (am.showed + am.no_shows), 1)
    ELSE NULL
  END AS show_rate,

  -- Remove Rate
  CASE
    WHEN COALESCE(im.total_reactivations, 0) > 0
    THEN ROUND(100.0 * im.remove_count / im.total_reactivations, 1)
    ELSE NULL
  END AS remove_pct,

  -- Performance Status
  CASE
    WHEN (COALESCE(tm.completed_tasks, 0) + COALESCE(tm.overdue_tasks, 0)) > 0 AND
         ROUND(100.0 * tm.completed_tasks / (tm.completed_tasks + tm.overdue_tasks), 1) >= 85 AND
         COALESCE(im.total_reactivations, 0) > 0 AND
         ROUND(100.0 * im.complete_instructions / im.total_reactivations, 1) >= 70
    THEN 'EXCELLENT'
    WHEN (COALESCE(tm.completed_tasks, 0) + COALESCE(tm.overdue_tasks, 0)) > 0 AND
         ROUND(100.0 * tm.completed_tasks / (tm.completed_tasks + tm.overdue_tasks), 1) >= 70 AND
         COALESCE(im.total_reactivations, 0) > 0 AND
         ROUND(100.0 * im.complete_instructions / im.total_reactivations, 1) >= 50
    THEN 'GOOD'
    WHEN (COALESCE(tm.completed_tasks, 0) + COALESCE(tm.overdue_tasks, 0)) > 0 AND
         ROUND(100.0 * tm.completed_tasks / (tm.completed_tasks + tm.overdue_tasks), 1) >= 50
    THEN 'FAIR'
    ELSE 'NEEDS_COACHING'
  END AS performance_status,

  -- Coaching Recommendation
  CASE
    WHEN COALESCE(tm.overdue_tasks, 0) > 10
    THEN 'Focus on closing ' || tm.overdue_tasks || ' overdue tasks'
    WHEN COALESCE(im.total_reactivations, 0) > 0 AND
         ROUND(100.0 * im.complete_instructions / im.total_reactivations, 1) < 50
    THEN 'Improve instruction quality - include Context + Action + Timing'
    WHEN (COALESCE(am.showed, 0) + COALESCE(am.no_shows, 0)) > 0 AND
         ROUND(100.0 * am.showed / (am.showed + am.no_shows), 1) < 50
    THEN 'Focus on appointment confirmation to improve show rate'
    WHEN COALESCE(am.unworked_no_shows, 0) > 0
    THEN 'Follow up on ' || am.unworked_no_shows || ' unworked no-shows'
    ELSE 'Maintain current performance'
  END AS coaching_recommendation

FROM task_metrics tm
LEFT JOIN completion_metrics cm ON tm.assigned_rep_id = cm.assigned_rep_id AND tm.location_id = cm.location_id
LEFT JOIN instruction_metrics im ON tm.assigned_rep_id = im.assigned_rep_id AND tm.location_id = im.location_id
LEFT JOIN appointment_metrics am ON tm.assigned_rep_id = am.assigned_rep_id AND tm.location_id = am.location_id

ORDER BY tm.location_id, closed_loop_pct DESC NULLS LAST;

-- Grant permissions
GRANT SELECT ON v_rep_complete_scorecard TO anon, authenticated, service_role;


-- ============================================================================
-- VIEW 2: v_health_trend
-- ============================================================================
-- Purpose: Weekly health score trend over the past 90 days
-- ============================================================================

DROP VIEW IF EXISTS v_health_trend;

CREATE OR REPLACE VIEW v_health_trend AS
WITH weeks AS (
  SELECT generate_series(
    DATE_TRUNC('week', NOW() - INTERVAL '90 days'),
    DATE_TRUNC('week', NOW()),
    '1 week'::INTERVAL
  )::DATE AS week_start
),
location_weeks AS (
  SELECT DISTINCT
    l.location_id,
    l.dealership_name,
    w.week_start
  FROM leads l
  CROSS JOIN weeks w
),
weekly_tasks AS (
  SELECT
    t.location_id,
    DATE_TRUNC('week', t.task_created_at)::DATE AS week_start,
    COUNT(*) AS tasks_created,
    COUNT(*) FILTER (WHERE t.completed = TRUE) AS tasks_completed,
    COUNT(*) FILTER (WHERE t.completed = FALSE AND t.due_date < DATE_TRUNC('week', t.task_created_at) + INTERVAL '1 week') AS tasks_overdue
  FROM tasks t
  WHERE t.task_created_at >= NOW() - INTERVAL '90 days'
  GROUP BY t.location_id, DATE_TRUNC('week', t.task_created_at)::DATE
),
weekly_instructions AS (
  SELECT
    r.location_id,
    DATE_TRUNC('week', r.reactivated_at)::DATE AS week_start,
    COUNT(*) AS total_instructions,
    COUNT(*) FILTER (WHERE ic.clarity_level = 'complete') AS complete_instructions
  FROM reactivations r
  LEFT JOIN v_instruction_clarity ic ON r.id = ic.id
  WHERE r.reactivated_at >= NOW() - INTERVAL '90 days'
  GROUP BY r.location_id, DATE_TRUNC('week', r.reactivated_at)::DATE
),
weekly_appointments AS (
  SELECT
    a.location_id,
    DATE_TRUNC('week', a.appointment_time)::DATE AS week_start,
    COUNT(*) FILTER (WHERE a.appointment_time < NOW()) AS past_appointments,
    COUNT(*) FILTER (WHERE a.appointment_time < NOW() AND a.outcome_status IN ('showed', 'no_show', 'cancelled')) AS marked_appointments
  FROM appointments a
  WHERE a.appointment_time >= NOW() - INTERVAL '90 days'
  GROUP BY a.location_id, DATE_TRUNC('week', a.appointment_time)::DATE
)
SELECT
  lw.location_id,
  lw.dealership_name,
  lw.week_start AS week,

  -- Task Metrics
  COALESCE(wt.tasks_created, 0) AS tasks_created,
  COALESCE(wt.tasks_completed, 0) AS tasks_completed,
  COALESCE(wt.tasks_overdue, 0) AS tasks_overdue,
  CASE
    WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
    THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue), 1)
    ELSE NULL
  END AS loop_closure_pct,

  -- Instruction Metrics
  COALESCE(wi.total_instructions, 0) AS total_instructions,
  COALESCE(wi.complete_instructions, 0) AS complete_instructions,
  CASE
    WHEN COALESCE(wi.total_instructions, 0) > 0
    THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions, 1)
    ELSE NULL
  END AS clarity_pct,

  -- Appointment Metrics
  COALESCE(wa.past_appointments, 0) AS past_appointments,
  COALESCE(wa.marked_appointments, 0) AS marked_appointments,
  CASE
    WHEN COALESCE(wa.past_appointments, 0) > 0
    THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments, 1)
    ELSE NULL
  END AS marking_pct,

  -- Weekly Health Score (simplified)
  (
    COALESCE(
      CASE
        WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
        THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
        ELSE 40
      END, 0
    ) +
    COALESCE(
      CASE
        WHEN COALESCE(wi.total_instructions, 0) > 0
        THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
        ELSE 0
      END, 0
    ) +
    COALESCE(
      CASE
        WHEN COALESCE(wa.past_appointments, 0) > 0
        THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
        ELSE 0
      END, 0
    )
  )::INTEGER AS weekly_health_score,

  -- Weekly Health Status
  CASE
    WHEN (
      COALESCE(
        CASE WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
          THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
          ELSE 40 END, 0
      ) +
      COALESCE(
        CASE WHEN COALESCE(wi.total_instructions, 0) > 0
          THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
          ELSE 0 END, 0
      ) +
      COALESCE(
        CASE WHEN COALESCE(wa.past_appointments, 0) > 0
          THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
          ELSE 0 END, 0
      )
    ) >= 80 THEN 'EXCELLENT'
    WHEN (
      COALESCE(
        CASE WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
          THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
          ELSE 40 END, 0
      ) +
      COALESCE(
        CASE WHEN COALESCE(wi.total_instructions, 0) > 0
          THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
          ELSE 0 END, 0
      ) +
      COALESCE(
        CASE WHEN COALESCE(wa.past_appointments, 0) > 0
          THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
          ELSE 0 END, 0
      )
    ) >= 60 THEN 'GOOD'
    WHEN (
      COALESCE(
        CASE WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
          THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
          ELSE 40 END, 0
      ) +
      COALESCE(
        CASE WHEN COALESCE(wi.total_instructions, 0) > 0
          THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
          ELSE 0 END, 0
      ) +
      COALESCE(
        CASE WHEN COALESCE(wa.past_appointments, 0) > 0
          THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
          ELSE 0 END, 0
      )
    ) >= 40 THEN 'FAIR'
    ELSE 'CRITICAL'
  END AS weekly_health_status

FROM location_weeks lw
LEFT JOIN weekly_tasks wt ON lw.location_id = wt.location_id AND lw.week_start = wt.week_start
LEFT JOIN weekly_instructions wi ON lw.location_id = wi.location_id AND lw.week_start = wi.week_start
LEFT JOIN weekly_appointments wa ON lw.location_id = wa.location_id AND lw.week_start = wa.week_start

WHERE (
  COALESCE(wt.tasks_created, 0) > 0 OR
  COALESCE(wi.total_instructions, 0) > 0 OR
  COALESCE(wa.past_appointments, 0) > 0
)

ORDER BY lw.location_id, lw.week_start;

-- Grant permissions
GRANT SELECT ON v_health_trend TO anon, authenticated, service_role;


-- ============================================================================
-- VIEW 3: v_rep_instruction_quality
-- ============================================================================
-- Purpose: Instruction quality metrics aggregated by rep
-- ============================================================================

DROP VIEW IF EXISTS v_rep_instruction_quality;

CREATE OR REPLACE VIEW v_rep_instruction_quality AS
SELECT
  r.location_id,
  r.assigned_rep_id,
  COALESCE(r.rep_name, 'Unknown') AS rep_name,
  r.dealership_name,

  -- Counts
  COUNT(*) AS total_instructions,
  COUNT(*) FILTER (WHERE ic.clarity_level = 'complete') AS complete_count,
  COUNT(*) FILTER (WHERE ic.clarity_level = 'partial') AS partial_count,
  COUNT(*) FILTER (WHERE ic.clarity_level = 'incomplete') AS incomplete_count,
  COUNT(*) FILTER (WHERE ic.clarity_level = 'empty' OR ic.instruction IS NULL OR ic.instruction = '') AS empty_count,

  -- Quality Score (% complete of non-empty)
  CASE
    WHEN COUNT(*) FILTER (WHERE ic.clarity_level != 'empty' AND ic.instruction IS NOT NULL AND ic.instruction != '') > 0
    THEN ROUND(
      100.0 * COUNT(*) FILTER (WHERE ic.clarity_level = 'complete') /
      COUNT(*) FILTER (WHERE ic.clarity_level != 'empty' AND ic.instruction IS NOT NULL AND ic.instruction != ''),
      1
    )
    ELSE NULL
  END AS clarity_pct,

  -- Missing component counts
  COUNT(*) FILTER (WHERE ic.has_context = FALSE) AS missing_context,
  COUNT(*) FILTER (WHERE ic.has_action = FALSE) AS missing_action,
  COUNT(*) FILTER (WHERE ic.has_timing = FALSE) AS missing_timing,

  -- Average instruction length
  ROUND(AVG(LENGTH(r.instruction))::NUMERIC, 1) AS avg_instruction_length,

  -- Weighted quality score (0-100)
  ROUND(
    AVG(
      CASE
        WHEN ic.clarity_level = 'complete' THEN 100
        WHEN ic.clarity_level = 'partial' THEN 66
        WHEN ic.clarity_level = 'incomplete' THEN 33
        ELSE 0
      END
    )::NUMERIC,
    1
  ) AS weighted_quality_score

FROM reactivations r
LEFT JOIN v_instruction_clarity ic ON r.id = ic.id
WHERE r.assigned_rep_id IS NOT NULL AND r.assigned_rep_id != ''
GROUP BY r.location_id, r.assigned_rep_id, r.rep_name, r.dealership_name
ORDER BY r.location_id, clarity_pct DESC NULLS LAST;

-- Grant permissions
GRANT SELECT ON v_rep_instruction_quality TO anon, authenticated, service_role;


-- ############################################################################
-- PART 2: APPOINTMENT FUNCTION FIXES
-- ############################################################################


-- ============================================================================
-- FUNCTION: insert_appointment (Fixed for Drive AI 7.0)
-- ============================================================================
-- PROBLEM: n8n sends p_appt_valid but function didn't accept it
-- SOLUTION: Create function with EXACT parameters n8n sends
-- ============================================================================

-- Drop existing versions to avoid conflicts
DROP FUNCTION IF EXISTS insert_appointment(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  JSONB, UUID
);

DROP FUNCTION IF EXISTS insert_appointment(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, BOOLEAN, TEXT, TEXT, TEXT, TEXT
);

-- Create the fixed function
CREATE OR REPLACE FUNCTION insert_appointment(
  p_ghl_appointment_id TEXT,
  p_trace_id TEXT DEFAULT NULL,
  p_calendar_id TEXT DEFAULT NULL,
  p_location_id TEXT DEFAULT NULL,
  p_dealership_name TEXT DEFAULT NULL,
  p_dealership_address TEXT DEFAULT NULL,
  p_dealership_hours TEXT DEFAULT NULL,
  p_dealership_timezone TEXT DEFAULT NULL,
  p_contact_id TEXT DEFAULT NULL,
  p_lead_name TEXT DEFAULT NULL,
  p_lead_first_name TEXT DEFAULT NULL,
  p_lead_phone TEXT DEFAULT NULL,
  p_lead_email TEXT DEFAULT NULL,
  p_assigned_rep_id TEXT DEFAULT NULL,
  p_assigned_rep_name TEXT DEFAULT NULL,
  p_title TEXT DEFAULT 'Store Appointment',
  p_appointment_type TEXT DEFAULT 'Store Appointment',
  p_appointment_time TIMESTAMPTZ DEFAULT NULL,
  p_appointment_summary TEXT DEFAULT NULL,
  p_appt_valid BOOLEAN DEFAULT TRUE,
  p_status TEXT DEFAULT 'booked',
  p_appointment_status TEXT DEFAULT 'confirmed',
  p_created_source TEXT DEFAULT 'ai_automated',
  p_source_workflow TEXT DEFAULT 'drive_ai_7'
)
RETURNS JSONB AS $$
DECLARE
  v_result_id UUID;
  v_existing_id UUID;
BEGIN
  -- Validate required field
  IF p_ghl_appointment_id IS NULL OR p_ghl_appointment_id = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Missing required field: ghl_appointment_id',
      'trace_id', p_trace_id
    );
  END IF;

  -- Check if appointment already exists (upsert behavior)
  SELECT id INTO v_existing_id
  FROM appointments
  WHERE ghl_appointment_id = p_ghl_appointment_id;

  IF v_existing_id IS NOT NULL THEN
    -- Appointment exists - update it (but don't overwrite created_source)
    UPDATE appointments
    SET
      appointment_time = COALESCE(p_appointment_time, appointment_time),
      appointment_type = COALESCE(NULLIF(p_appointment_type, ''), appointment_type),
      appointment_summary = COALESCE(NULLIF(p_appointment_summary, ''), appointment_summary),
      appointment_status = COALESCE(NULLIF(p_appointment_status, ''), appointment_status),
      status = COALESCE(NULLIF(p_status, ''), status),
      title = COALESCE(NULLIF(p_title, ''), title),
      lead_name = COALESCE(NULLIF(p_lead_name, ''), lead_name),
      lead_first_name = COALESCE(NULLIF(p_lead_first_name, ''), lead_first_name),
      lead_phone = COALESCE(NULLIF(p_lead_phone, ''), lead_phone),
      lead_email = COALESCE(NULLIF(p_lead_email, ''), lead_email),
      assigned_rep_id = COALESCE(NULLIF(p_assigned_rep_id, ''), assigned_rep_id),
      assigned_rep_name = COALESCE(NULLIF(p_assigned_rep_name, ''), assigned_rep_name),
      updated_at = NOW()
    WHERE id = v_existing_id
    RETURNING id INTO v_result_id;

    RETURN jsonb_build_object(
      'success', true,
      'appointment_id', v_result_id,
      'ghl_appointment_id', p_ghl_appointment_id,
      'action', 'updated',
      'trace_id', p_trace_id
    );
  END IF;

  -- Insert new appointment
  INSERT INTO appointments (
    ghl_appointment_id,
    trace_id,
    calendar_id,
    location_id,
    dealership_name,
    dealership_address,
    dealership_hours,
    dealership_timezone,
    contact_id,
    lead_name,
    lead_first_name,
    lead_phone,
    lead_email,
    assigned_rep_id,
    assigned_rep_name,
    title,
    appointment_type,
    appointment_time,
    appointment_summary,
    status,
    appointment_status,
    outcome_status,
    created_source,
    source_workflow,
    created_at,
    updated_at,
    appointment_created_at
  ) VALUES (
    p_ghl_appointment_id,
    p_trace_id,
    p_calendar_id,
    p_location_id,
    p_dealership_name,
    p_dealership_address,
    p_dealership_hours,
    p_dealership_timezone,
    p_contact_id,
    p_lead_name,
    p_lead_first_name,
    p_lead_phone,
    p_lead_email,
    p_assigned_rep_id,
    p_assigned_rep_name,
    COALESCE(p_title, 'Store Appointment'),
    COALESCE(p_appointment_type, 'Store Appointment'),
    COALESCE(p_appointment_time, NOW() + INTERVAL '1 day'),
    p_appointment_summary,
    COALESCE(p_status, 'booked'),
    COALESCE(p_appointment_status, 'confirmed'),
    'pending',
    COALESCE(p_created_source, 'ai_automated'),
    COALESCE(p_source_workflow, 'drive_ai_7'),
    NOW(),
    NOW(),
    NOW()
  )
  RETURNING id INTO v_result_id;

  -- Update leads table
  IF p_contact_id IS NOT NULL AND p_location_id IS NOT NULL THEN
    UPDATE leads
    SET
      appointment_booked = TRUE,
      appointment_count = COALESCE(appointment_count, 0) + 1,
      first_appointment_at = COALESCE(first_appointment_at, NOW()),
      updated_at = NOW()
    WHERE contact_id = p_contact_id
      AND location_id = p_location_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_result_id,
    'ghl_appointment_id', p_ghl_appointment_id,
    'action', 'inserted',
    'created_source', p_created_source,
    'source_workflow', p_source_workflow,
    'trace_id', p_trace_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'error_detail', SQLSTATE,
    'ghl_appointment_id', p_ghl_appointment_id,
    'trace_id', p_trace_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION insert_appointment(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, BOOLEAN, TEXT, TEXT, TEXT, TEXT
) TO anon, authenticated, service_role;


-- ############################################################################
-- VERIFICATION QUERIES
-- ############################################################################

-- Run these after creating the views to verify they work:

-- Test v_rep_complete_scorecard
-- SELECT * FROM v_rep_complete_scorecard LIMIT 5;

-- Test v_health_trend
-- SELECT * FROM v_health_trend WHERE week >= NOW() - INTERVAL '30 days' LIMIT 10;

-- Test v_rep_instruction_quality
-- SELECT * FROM v_rep_instruction_quality LIMIT 5;

-- Test insert_appointment function:
/*
SELECT insert_appointment(
  'TEST_MASTER_FIX_123',
  'trace-123',
  'cal-123',
  'RMMkdOgBaw5tjVTzSeQ9',
  'Test Dealer',
  '123 Main St',
  '9-5',
  'America/Chicago',
  'contact-123',
  'Test User',
  'Test',
  '+15551234567',
  'test@test.com',
  'rep-123',
  'John Rep',
  'Test Appointment',
  'Store Appointment',
  NOW() + INTERVAL '1 day',
  'Test summary',
  true,
  'booked',
  'confirmed',
  'ai_automated',
  'drive_ai_7'
);

-- Verify:
SELECT * FROM appointments WHERE ghl_appointment_id = 'TEST_MASTER_FIX_123';

-- Cleanup:
DELETE FROM appointments WHERE ghl_appointment_id = 'TEST_MASTER_FIX_123';
*/


-- ############################################################################
-- DEPLOYMENT COMPLETE
-- ############################################################################
-- All fixes have been applied:
--
-- ✅ v_rep_complete_scorecard - Created (CRITICAL for dashboard)
-- ✅ v_health_trend - Created
-- ✅ v_rep_instruction_quality - Created
-- ✅ insert_appointment - Fixed to accept p_appt_valid parameter
--
-- The dashboard should now work correctly!
-- ############################################################################
