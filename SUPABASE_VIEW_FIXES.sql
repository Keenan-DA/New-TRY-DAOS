-- ============================================================================
-- DRIVE AI 7.0 - COMPREHENSIVE VIEW FIXES
-- ============================================================================
-- Generated: January 20, 2026
-- Purpose: Fix all missing/broken views discovered during testing
--
-- MISSING VIEWS FOUND:
--   1. v_rep_complete_scorecard (CRITICAL - used by dashboard!)
--   2. v_health_trend (Used for trend tracking)
--   3. v_rep_instruction_quality (Rep instruction quality aggregation)
--
-- RUN THIS ENTIRE FILE IN SUPABASE SQL EDITOR
-- ============================================================================


-- ============================================================================
-- VIEW 1: v_rep_complete_scorecard
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


-- ============================================================================
-- VIEW 2: v_health_trend
-- ============================================================================
-- Purpose: Weekly health score trend over the past 90 days
-- Used by: Health trend charts and improvement tracking
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

  -- Weekly Health Score
  (
    CASE
      WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
      THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
      ELSE 40
    END +
    CASE
      WHEN COALESCE(wi.total_instructions, 0) > 0
      THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
      ELSE 0
    END +
    CASE
      WHEN COALESCE(wa.past_appointments, 0) > 0
      THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
      ELSE 0
    END
  )::INTEGER AS weekly_health_score,

  -- Weekly Health Status
  CASE
    WHEN (
      CASE
        WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
        THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
        ELSE 40
      END +
      CASE
        WHEN COALESCE(wi.total_instructions, 0) > 0
        THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
        ELSE 0
      END +
      CASE
        WHEN COALESCE(wa.past_appointments, 0) > 0
        THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
        ELSE 0
      END
    ) >= 80 THEN 'EXCELLENT'
    WHEN (
      CASE
        WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
        THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
        ELSE 40
      END +
      CASE
        WHEN COALESCE(wi.total_instructions, 0) > 0
        THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
        ELSE 0
      END +
      CASE
        WHEN COALESCE(wa.past_appointments, 0) > 0
        THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
        ELSE 0
      END
    ) >= 60 THEN 'GOOD'
    WHEN (
      CASE
        WHEN (COALESCE(wt.tasks_completed, 0) + COALESCE(wt.tasks_overdue, 0)) > 0
        THEN ROUND(100.0 * wt.tasks_completed / (wt.tasks_completed + wt.tasks_overdue) * 0.4)
        ELSE 40
      END +
      CASE
        WHEN COALESCE(wi.total_instructions, 0) > 0
        THEN ROUND(100.0 * wi.complete_instructions / wi.total_instructions * 0.3)
        ELSE 0
      END +
      CASE
        WHEN COALESCE(wa.past_appointments, 0) > 0
        THEN ROUND(100.0 * wa.marked_appointments / wa.past_appointments * 0.3)
        ELSE 0
      END
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


-- ============================================================================
-- VIEW 3: v_rep_instruction_quality
-- ============================================================================
-- Purpose: Instruction quality metrics aggregated by rep
-- Used by: Rep instruction quality analysis
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


-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT ON v_rep_complete_scorecard TO anon, authenticated, service_role;
GRANT SELECT ON v_health_trend TO anon, authenticated, service_role;
GRANT SELECT ON v_rep_instruction_quality TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- Run these after creating the views to verify they work:

-- Test v_rep_complete_scorecard
-- SELECT * FROM v_rep_complete_scorecard LIMIT 5;

-- Test v_health_trend
-- SELECT * FROM v_health_trend WHERE week >= NOW() - INTERVAL '30 days' LIMIT 10;

-- Test v_rep_instruction_quality
-- SELECT * FROM v_rep_instruction_quality LIMIT 5;


-- ============================================================================
-- SUMMARY OF FIXES
-- ============================================================================
--
-- 1. v_rep_complete_scorecard - Created
--    - Comprehensive rep performance metrics
--    - Loop closure % using accountable tasks formula
--    - Instruction quality (complete/partial/low)
--    - Appointment show rate
--    - Performance status and coaching recommendations
--
-- 2. v_health_trend - Created
--    - Weekly health metrics over 90 days
--    - Loop closure, clarity, and marking trends
--    - Weekly health score and status
--
-- 3. v_rep_instruction_quality - Created
--    - Instruction quality aggregated by rep
--    - Missing component analysis
--    - Weighted quality scoring
--
-- ============================================================================
