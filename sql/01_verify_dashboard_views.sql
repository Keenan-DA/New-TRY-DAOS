-- ============================================
-- DA-OS DASHBOARD VIEW VERIFICATION
-- Run these queries to verify all views the HTML needs
-- ============================================

-- QUERY 1: Check which required views exist
SELECT
    v.view_name,
    CASE WHEN v.view_name IN (
        'v_cs_account_health',
        'v_lost_opportunity',
        'v_pipeline_funnel',
        'v_rep_complete_scorecard',
        'v_instruction_log',
        'v_pipeline_funnel_by_source',
        'v_dealerships'
    ) THEN 'REQUIRED' ELSE 'optional' END as status
FROM (
    SELECT table_name as view_name
    FROM information_schema.views
    WHERE table_schema = 'public'
) v
WHERE v.view_name LIKE 'v_%'
ORDER BY
    CASE WHEN v.view_name IN (
        'v_cs_account_health',
        'v_lost_opportunity',
        'v_pipeline_funnel',
        'v_rep_complete_scorecard',
        'v_instruction_log',
        'v_pipeline_funnel_by_source',
        'v_dealerships'
    ) THEN 0 ELSE 1 END,
    v.view_name;

-- QUERY 2: Test v_cs_account_health (main dashboard)
SELECT location_id, dealership_name, adoption_score, health_status, compounding_rate
FROM v_cs_account_health
LIMIT 3;

-- QUERY 3: Test v_instruction_log
SELECT location_id, lead_name, instruction, action, clarity_level, reactivated_at
FROM v_instruction_log
LIMIT 3;

-- QUERY 4: Test v_lost_opportunity
SELECT location_id, dealership_name, overdue_tasks, est_lost_from_overdue
FROM v_lost_opportunity
LIMIT 3;

-- QUERY 5: Test v_pipeline_funnel
SELECT location_id, dealership_name, total_new_inbound, outbound_sent, total_responses, show_rate
FROM v_pipeline_funnel
LIMIT 3;

-- QUERY 6: Test v_rep_complete_scorecard
SELECT location_id, rep_name, total_tasks, completed_tasks, closed_loop_pct, clarity_pct
FROM v_rep_complete_scorecard
LIMIT 3;

-- QUERY 7: Test v_pipeline_funnel_by_source
SELECT location_id, lead_source, total_leads, reply_rate, booking_rate, show_rate
FROM v_pipeline_funnel_by_source
LIMIT 3;
