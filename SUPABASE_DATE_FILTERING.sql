-- ============================================================================
-- DRIVE AI 7.0 - Server-Side Date Filtering for Scale
-- ============================================================================
-- Run this SQL in your Supabase SQL Editor to enable date-filtered queries
-- This dramatically reduces data transfer for large datasets
-- ============================================================================

-- ============================================================================
-- FUNCTION 1: rpc_cs_account_health_by_date
-- ============================================================================
-- Returns account health metrics filtered by date range
-- This is the main function for the Portfolio Overview page
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_cs_account_health_by_date(
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  location_id TEXT,
  dealership_name TEXT,
  -- Lead metrics (filtered by date)
  total_leads BIGINT,
  responded_leads BIGINT,
  response_rate NUMERIC,
  new_leads_last_30 BIGINT,
  -- Task metrics (filtered by date)
  total_tasks BIGINT,
  completed_tasks BIGINT,
  overdue_tasks BIGINT,
  pending_tasks BIGINT,
  tasks_last_30 BIGINT,
  -- Loop closure
  closed_loop_pct NUMERIC,
  -- Instruction quality
  complete_instructions BIGINT,
  partial_instructions BIGINT,
  incomplete_instructions BIGINT,
  empty_instructions BIGINT,
  clarity_score NUMERIC,
  -- Appointments (filtered by date)
  total_appointments BIGINT,
  appointments_last_30 BIGINT,
  showed BIGINT,
  no_shows BIGINT,
  unmarked_appointments BIGINT,
  show_rate NUMERIC,
  marking_rate NUMERIC,
  -- Health scores
  adoption_score INTEGER,
  compounding_rate NUMERIC,
  -- Status
  risk_level TEXT,
  health_trend TEXT,
  primary_issue TEXT,
  days_since_activity INTEGER
) AS $$
DECLARE
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  -- Default to all time if no dates provided
  v_start_date := COALESCE(p_start_date, '1970-01-01'::TIMESTAMPTZ);
  v_end_date := COALESCE(p_end_date, NOW());

  RETURN QUERY
  WITH date_filtered_leads AS (
    SELECT
      l.location_id,
      l.dealership_name,
      COUNT(*) AS total_leads,
      COUNT(*) FILTER (WHERE l.responded = TRUE) AS responded_leads,
      COUNT(*) FILTER (WHERE l.lead_date >= NOW() - INTERVAL '30 days') AS new_leads_last_30
    FROM leads l
    WHERE l.lead_date BETWEEN v_start_date AND v_end_date
    GROUP BY l.location_id, l.dealership_name
  ),
  date_filtered_tasks AS (
    SELECT
      t.location_id,
      COUNT(*) AS total_tasks,
      COUNT(*) FILTER (WHERE t.completed = TRUE) AS completed_tasks,
      COUNT(*) FILTER (WHERE t.completed = FALSE AND t.due_date < NOW()) AS overdue_tasks,
      COUNT(*) FILTER (WHERE t.completed = FALSE AND (t.due_date >= NOW() OR t.due_date IS NULL)) AS pending_tasks,
      COUNT(*) FILTER (WHERE t.task_created_at >= NOW() - INTERVAL '30 days') AS tasks_last_30
    FROM tasks t
    WHERE t.task_created_at BETWEEN v_start_date AND v_end_date
    GROUP BY t.location_id
  ),
  date_filtered_reactivations AS (
    SELECT
      r.location_id,
      COUNT(*) FILTER (WHERE r.clarity_level = 'complete') AS complete_instructions,
      COUNT(*) FILTER (WHERE r.clarity_level = 'partial') AS partial_instructions,
      COUNT(*) FILTER (WHERE r.clarity_level = 'incomplete') AS incomplete_instructions,
      COUNT(*) FILTER (WHERE r.clarity_level = 'empty' OR r.clarity_level IS NULL) AS empty_instructions,
      MAX(r.reactivated_at) AS last_activity
    FROM reactivations r
    WHERE r.reactivated_at BETWEEN v_start_date AND v_end_date
    GROUP BY r.location_id
  ),
  date_filtered_appointments AS (
    SELECT
      a.location_id,
      COUNT(*) AS total_appointments,
      COUNT(*) FILTER (WHERE a.appointment_time >= NOW() - INTERVAL '30 days') AS appointments_last_30,
      COUNT(*) FILTER (WHERE a.outcome_status = 'showed') AS showed,
      COUNT(*) FILTER (WHERE a.outcome_status = 'no_show') AS no_shows,
      COUNT(*) FILTER (WHERE a.appointment_time < NOW() AND (a.outcome_status IS NULL OR a.outcome_status = '')) AS unmarked_appointments
    FROM appointments a
    WHERE a.appointment_time BETWEEN v_start_date AND v_end_date
    GROUP BY a.location_id
  )
  SELECT
    l.location_id,
    l.dealership_name,
    -- Leads
    COALESCE(l.total_leads, 0)::BIGINT,
    COALESCE(l.responded_leads, 0)::BIGINT,
    CASE WHEN l.total_leads > 0
      THEN ROUND(100.0 * l.responded_leads / l.total_leads, 1)
      ELSE 0
    END::NUMERIC AS response_rate,
    COALESCE(l.new_leads_last_30, 0)::BIGINT,
    -- Tasks
    COALESCE(t.total_tasks, 0)::BIGINT,
    COALESCE(t.completed_tasks, 0)::BIGINT,
    COALESCE(t.overdue_tasks, 0)::BIGINT,
    COALESCE(t.pending_tasks, 0)::BIGINT,
    COALESCE(t.tasks_last_30, 0)::BIGINT,
    -- Loop closure
    CASE WHEN (COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0)) > 0
      THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks), 1)
      ELSE 100
    END::NUMERIC AS closed_loop_pct,
    -- Instructions
    COALESCE(r.complete_instructions, 0)::BIGINT,
    COALESCE(r.partial_instructions, 0)::BIGINT,
    COALESCE(r.incomplete_instructions, 0)::BIGINT,
    COALESCE(r.empty_instructions, 0)::BIGINT,
    -- Clarity score
    CASE WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
               COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0
      THEN ROUND(100.0 * r.complete_instructions /
           (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions), 1)
      ELSE 0
    END::NUMERIC AS clarity_score,
    -- Appointments
    COALESCE(a.total_appointments, 0)::BIGINT,
    COALESCE(a.appointments_last_30, 0)::BIGINT,
    COALESCE(a.showed, 0)::BIGINT,
    COALESCE(a.no_shows, 0)::BIGINT,
    COALESCE(a.unmarked_appointments, 0)::BIGINT,
    -- Show rate
    CASE WHEN (COALESCE(a.showed, 0) + COALESCE(a.no_shows, 0)) > 0
      THEN ROUND(100.0 * a.showed / (a.showed + a.no_shows), 1)
      ELSE 0
    END::NUMERIC AS show_rate,
    -- Marking rate
    CASE WHEN COALESCE(a.total_appointments, 0) > 0
      THEN ROUND(100.0 * (a.showed + a.no_shows) / a.total_appointments, 1)
      ELSE 0
    END::NUMERIC AS marking_rate,
    -- Adoption score (weighted: 40% loop, 30% clarity, 30% marking)
    (
      CASE WHEN (COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0)) > 0
        THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) * 0.4)
        ELSE 40
      END +
      CASE WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
                 COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0
        THEN ROUND(100.0 * r.complete_instructions /
             (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions) * 0.3)
        ELSE 0
      END +
      CASE WHEN COALESCE(a.total_appointments, 0) > 0
        THEN ROUND(100.0 * (a.showed + a.no_shows) / a.total_appointments * 0.3)
        ELSE 0
      END
    )::INTEGER AS adoption_score,
    -- Compounding rate (always L30D)
    CASE WHEN COALESCE(l.new_leads_last_30, 0) > 0
      THEN ROUND(100.0 * (COALESCE(t.tasks_last_30, 0) + COALESCE(a.appointments_last_30, 0)) / l.new_leads_last_30, 1)
      ELSE 0
    END::NUMERIC AS compounding_rate,
    -- Risk level
    CASE
      WHEN (
        CASE WHEN (COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0)) > 0
          THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) * 0.4)
          ELSE 40
        END +
        CASE WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
                   COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0
          THEN ROUND(100.0 * r.complete_instructions /
               (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions) * 0.3)
          ELSE 0
        END +
        CASE WHEN COALESCE(a.total_appointments, 0) > 0
          THEN ROUND(100.0 * (a.showed + a.no_shows) / a.total_appointments * 0.3)
          ELSE 0
        END
      ) < 40 THEN 'CRITICAL'
      WHEN (
        CASE WHEN (COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0)) > 0
          THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) * 0.4)
          ELSE 40
        END +
        CASE WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
                   COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0
          THEN ROUND(100.0 * r.complete_instructions /
               (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions) * 0.3)
          ELSE 0
        END +
        CASE WHEN COALESCE(a.total_appointments, 0) > 0
          THEN ROUND(100.0 * (a.showed + a.no_shows) / a.total_appointments * 0.3)
          ELSE 0
        END
      ) < 50 THEN 'AT_RISK'
      WHEN (
        CASE WHEN (COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0)) > 0
          THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) * 0.4)
          ELSE 40
        END +
        CASE WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
                   COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0
          THEN ROUND(100.0 * r.complete_instructions /
               (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions) * 0.3)
          ELSE 0
        END +
        CASE WHEN COALESCE(a.total_appointments, 0) > 0
          THEN ROUND(100.0 * (a.showed + a.no_shows) / a.total_appointments * 0.3)
          ELSE 0
        END
      ) < 60 THEN 'NEEDS_ATTENTION'
      WHEN (
        CASE WHEN (COALESCE(t.completed_tasks, 0) + COALESCE(t.overdue_tasks, 0)) > 0
          THEN ROUND(100.0 * t.completed_tasks / (t.completed_tasks + t.overdue_tasks) * 0.4)
          ELSE 40
        END +
        CASE WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
                   COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0
          THEN ROUND(100.0 * r.complete_instructions /
               (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions) * 0.3)
          ELSE 0
        END +
        CASE WHEN COALESCE(a.total_appointments, 0) > 0
          THEN ROUND(100.0 * (a.showed + a.no_shows) / a.total_appointments * 0.3)
          ELSE 0
        END
      ) >= 70 THEN 'HEALTHY'
      ELSE 'NEEDS_ATTENTION'
    END::TEXT AS risk_level,
    -- Health trend (placeholder - would need historical comparison)
    'STABLE'::TEXT AS health_trend,
    -- Primary issue
    CASE
      WHEN COALESCE(t.overdue_tasks, 0) > 10 THEN 'High number of overdue tasks'
      WHEN COALESCE(a.unmarked_appointments, 0) > 5 THEN 'Many unmarked appointments'
      WHEN (COALESCE(r.complete_instructions, 0) + COALESCE(r.partial_instructions, 0) +
            COALESCE(r.incomplete_instructions, 0) + COALESCE(r.empty_instructions, 0)) > 0 AND
           ROUND(100.0 * r.complete_instructions /
           (r.complete_instructions + r.partial_instructions + r.incomplete_instructions + r.empty_instructions), 1) < 50
        THEN 'Low instruction quality'
      ELSE 'Account healthy'
    END::TEXT AS primary_issue,
    -- Days since activity
    EXTRACT(DAY FROM NOW() - COALESCE(r.last_activity, NOW() - INTERVAL '999 days'))::INTEGER AS days_since_activity
  FROM date_filtered_leads l
  LEFT JOIN date_filtered_tasks t ON t.location_id = l.location_id
  LEFT JOIN date_filtered_reactivations r ON r.location_id = l.location_id
  LEFT JOIN date_filtered_appointments a ON a.location_id = l.location_id
  ORDER BY l.dealership_name;
END;
$$ LANGUAGE plpgsql STABLE;

-- Grant access
GRANT EXECUTE ON FUNCTION rpc_cs_account_health_by_date TO anon, authenticated;


-- ============================================================================
-- FUNCTION 2: rpc_instruction_log_by_date
-- ============================================================================
-- Returns instruction log entries filtered by date range
-- For the Instruction Log section in Client Detail page
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_instruction_log_by_date(
  p_location_id TEXT DEFAULT NULL,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  location_id TEXT,
  contact_id TEXT,
  lead_name TEXT,
  assigned_rep_name TEXT,
  rep_name TEXT,
  instruction TEXT,
  action TEXT,
  follow_up_date TIMESTAMPTZ,
  follow_up_message TEXT,
  appointment_time TIMESTAMPTZ,
  appointment_summary TEXT,
  clarity_level TEXT,
  has_context BOOLEAN,
  has_action BOOLEAN,
  has_timing BOOLEAN,
  reactivated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
) AS $$
DECLARE
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  -- Default to all time if no dates provided
  v_start_date := COALESCE(p_start_date, '1970-01-01'::TIMESTAMPTZ);
  v_end_date := COALESCE(p_end_date, NOW() + INTERVAL '1 year');

  RETURN QUERY
  SELECT
    r.id,
    r.location_id,
    r.contact_id,
    COALESCE(r.lead_name, l.lead_name, 'Unknown')::TEXT AS lead_name,
    r.assigned_rep_name,
    r.assigned_rep_name AS rep_name,
    r.instruction,
    r.action,
    r.follow_up_date,
    r.follow_up_message,
    r.appointment_time,
    r.appointment_summary,
    r.clarity_level,
    (r.instruction IS NOT NULL AND r.instruction != '' AND LENGTH(r.instruction) > 10)::BOOLEAN AS has_context,
    (r.action IS NOT NULL AND r.action != '')::BOOLEAN AS has_action,
    (r.follow_up_date IS NOT NULL OR r.appointment_time IS NOT NULL)::BOOLEAN AS has_timing,
    r.reactivated_at,
    r.created_at
  FROM reactivations r
  LEFT JOIN leads l ON l.contact_id = r.contact_id
  WHERE
    (p_location_id IS NULL OR r.location_id = p_location_id)
    AND r.reactivated_at BETWEEN v_start_date AND v_end_date
  ORDER BY r.reactivated_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- Grant access
GRANT EXECUTE ON FUNCTION rpc_instruction_log_by_date TO anon, authenticated;


-- ============================================================================
-- FUNCTION 3: rpc_pipeline_funnel_by_date
-- ============================================================================
-- Returns pipeline funnel data filtered by date range
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_pipeline_funnel_by_date(
  p_location_id TEXT DEFAULT NULL,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  location_id TEXT,
  dealership_name TEXT,
  total_leads BIGINT,
  responded BIGINT,
  tasks_created BIGINT,
  appointments_booked BIGINT,
  showed BIGINT,
  no_shows BIGINT,
  opt_outs BIGINT,
  response_rate NUMERIC,
  task_rate NUMERIC,
  appointment_rate NUMERIC,
  show_rate NUMERIC
) AS $$
DECLARE
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  v_start_date := COALESCE(p_start_date, '1970-01-01'::TIMESTAMPTZ);
  v_end_date := COALESCE(p_end_date, NOW());

  RETURN QUERY
  SELECT
    l.location_id,
    l.dealership_name,
    COUNT(DISTINCT l.contact_id)::BIGINT AS total_leads,
    COUNT(DISTINCT l.contact_id) FILTER (WHERE l.responded = TRUE)::BIGINT AS responded,
    COUNT(DISTINCT t.contact_id)::BIGINT AS tasks_created,
    COUNT(DISTINCT a.contact_id)::BIGINT AS appointments_booked,
    COUNT(DISTINCT a.contact_id) FILTER (WHERE a.outcome_status = 'showed')::BIGINT AS showed,
    COUNT(DISTINCT a.contact_id) FILTER (WHERE a.outcome_status = 'no_show')::BIGINT AS no_shows,
    COUNT(DISTINCT l.contact_id) FILTER (WHERE l.status = 'removed')::BIGINT AS opt_outs,
    -- Rates
    CASE WHEN COUNT(DISTINCT l.contact_id) > 0
      THEN ROUND(100.0 * COUNT(DISTINCT l.contact_id) FILTER (WHERE l.responded = TRUE) / COUNT(DISTINCT l.contact_id), 1)
      ELSE 0
    END::NUMERIC AS response_rate,
    CASE WHEN COUNT(DISTINCT l.contact_id) > 0
      THEN ROUND(100.0 * COUNT(DISTINCT t.contact_id) / COUNT(DISTINCT l.contact_id), 1)
      ELSE 0
    END::NUMERIC AS task_rate,
    CASE WHEN COUNT(DISTINCT l.contact_id) > 0
      THEN ROUND(100.0 * COUNT(DISTINCT a.contact_id) / COUNT(DISTINCT l.contact_id), 1)
      ELSE 0
    END::NUMERIC AS appointment_rate,
    CASE WHEN COUNT(DISTINCT a.contact_id) > 0
      THEN ROUND(100.0 * COUNT(DISTINCT a.contact_id) FILTER (WHERE a.outcome_status = 'showed') / COUNT(DISTINCT a.contact_id), 1)
      ELSE 0
    END::NUMERIC AS show_rate
  FROM leads l
  LEFT JOIN tasks t ON t.contact_id = l.contact_id AND t.task_created_at BETWEEN v_start_date AND v_end_date
  LEFT JOIN appointments a ON a.contact_id = l.contact_id AND a.appointment_time BETWEEN v_start_date AND v_end_date
  WHERE
    l.lead_date BETWEEN v_start_date AND v_end_date
    AND (p_location_id IS NULL OR l.location_id = p_location_id)
  GROUP BY l.location_id, l.dealership_name
  ORDER BY l.dealership_name;
END;
$$ LANGUAGE plpgsql STABLE;

-- Grant access
GRANT EXECUTE ON FUNCTION rpc_pipeline_funnel_by_date TO anon, authenticated;


-- ============================================================================
-- FUNCTION 4: rpc_lost_opportunity_by_date
-- ============================================================================
-- Returns lost opportunity analysis filtered by date range
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_lost_opportunity_by_date(
  p_location_id TEXT,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  location_id TEXT,
  overdue_tasks BIGINT,
  poor_instructions BIGINT,
  task_to_appt_rate NUMERIC,
  estimated_lost_from_overdue NUMERIC,
  estimated_lost_from_poor_quality NUMERIC,
  total_estimated_lost NUMERIC
) AS $$
DECLARE
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  v_start_date := COALESCE(p_start_date, '1970-01-01'::TIMESTAMPTZ);
  v_end_date := COALESCE(p_end_date, NOW());

  RETURN QUERY
  WITH task_metrics AS (
    SELECT
      t.location_id,
      COUNT(*) FILTER (WHERE t.completed = FALSE AND t.due_date < NOW()) AS overdue_tasks,
      COUNT(*) AS total_tasks,
      COUNT(*) FILTER (WHERE t.completed = TRUE) AS completed_tasks
    FROM tasks t
    WHERE t.location_id = p_location_id
      AND t.task_created_at BETWEEN v_start_date AND v_end_date
    GROUP BY t.location_id
  ),
  instruction_metrics AS (
    SELECT
      r.location_id,
      COUNT(*) FILTER (WHERE r.clarity_level IN ('incomplete', 'empty') OR r.clarity_level IS NULL) AS poor_instructions
    FROM reactivations r
    WHERE r.location_id = p_location_id
      AND r.reactivated_at BETWEEN v_start_date AND v_end_date
    GROUP BY r.location_id
  ),
  appointment_metrics AS (
    SELECT
      a.location_id,
      COUNT(*) AS total_appointments
    FROM appointments a
    WHERE a.location_id = p_location_id
      AND a.appointment_time BETWEEN v_start_date AND v_end_date
    GROUP BY a.location_id
  )
  SELECT
    p_location_id::TEXT AS location_id,
    COALESCE(tm.overdue_tasks, 0)::BIGINT,
    COALESCE(im.poor_instructions, 0)::BIGINT,
    CASE WHEN COALESCE(tm.completed_tasks, 0) > 0
      THEN ROUND(100.0 * COALESCE(am.total_appointments, 0) / tm.completed_tasks, 1)
      ELSE 0
    END::NUMERIC AS task_to_appt_rate,
    -- Estimated lost from overdue (assume 24% conversion rate)
    ROUND(COALESCE(tm.overdue_tasks, 0) * 0.24, 1)::NUMERIC AS estimated_lost_from_overdue,
    -- Estimated lost from poor quality (assume 50% reduction)
    ROUND(COALESCE(im.poor_instructions, 0) * 0.12, 1)::NUMERIC AS estimated_lost_from_poor_quality,
    -- Total
    ROUND(COALESCE(tm.overdue_tasks, 0) * 0.24 + COALESCE(im.poor_instructions, 0) * 0.12, 1)::NUMERIC AS total_estimated_lost
  FROM task_metrics tm
  FULL OUTER JOIN instruction_metrics im ON im.location_id = tm.location_id
  FULL OUTER JOIN appointment_metrics am ON am.location_id = COALESCE(tm.location_id, im.location_id);
END;
$$ LANGUAGE plpgsql STABLE;

-- Grant access
GRANT EXECUTE ON FUNCTION rpc_lost_opportunity_by_date TO anon, authenticated;


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- Run these to verify the functions work correctly

-- Test 1: Get all account health (no date filter)
-- SELECT * FROM rpc_cs_account_health_by_date();

-- Test 2: Get account health for last 30 days
-- SELECT * FROM rpc_cs_account_health_by_date(NOW() - INTERVAL '30 days', NOW());

-- Test 3: Get instruction log for specific location
-- SELECT * FROM rpc_instruction_log_by_date('your_location_id_here');

-- Test 4: Get instruction log for date range
-- SELECT * FROM rpc_instruction_log_by_date(NULL, NOW() - INTERVAL '7 days', NOW());

-- ============================================================================
-- END OF FILE
-- ============================================================================
