-- ============================================
-- DA-OS DATA VALIDATION QUERIES
-- Run each query separately and share results
-- ============================================

-- QUERY 1: Row counts for all tables
SELECT 'leads' as table_name, COUNT(*) as row_count FROM leads
UNION ALL SELECT 'tasks', COUNT(*) FROM tasks
UNION ALL SELECT 'reactivations', COUNT(*) FROM reactivations
UNION ALL SELECT 'appointments', COUNT(*) FROM appointments
UNION ALL SELECT 'ai_decisions', COUNT(*) FROM ai_decisions
UNION ALL SELECT 'task_completions', COUNT(*) FROM task_completions
UNION ALL SELECT 'lead_source_dictionary', COUNT(*) FROM lead_source_dictionary;

-- QUERY 2: Test v_cs_account_health (main dashboard view) - first 5 rows
SELECT
    location_id,
    dealership_name,
    adoption_score,
    health_status,
    risk_level,
    compounding_rate,
    total_tasks,
    completed_tasks,
    overdue_tasks,
    total_leads,
    appointments_last_30
FROM v_cs_account_health
LIMIT 5;

-- QUERY 3: Test v_pipeline_funnel - first 5 rows
SELECT * FROM v_pipeline_funnel LIMIT 5;

-- QUERY 4: Test v_rep_complete_scorecard - first 5 rows
SELECT * FROM v_rep_complete_scorecard LIMIT 5;

-- QUERY 5: Test v_lost_opportunity - first 5 rows
SELECT * FROM v_lost_opportunity LIMIT 5;

-- QUERY 6: Check data distribution by location
SELECT
    location_id,
    COUNT(*) as lead_count,
    COUNT(CASE WHEN responded = true THEN 1 END) as responded_count,
    COUNT(CASE WHEN appointment_booked = true THEN 1 END) as booked_count
FROM leads
GROUP BY location_id
ORDER BY lead_count DESC
LIMIT 10;

-- QUERY 7: Check tasks status distribution
SELECT
    location_id,
    COUNT(*) as total_tasks,
    COUNT(CASE WHEN completed = true THEN 1 END) as completed,
    COUNT(CASE WHEN completed = false AND due_date < NOW() THEN 1 END) as overdue,
    COUNT(CASE WHEN completed = false AND due_date >= NOW() THEN 1 END) as pending
FROM tasks
GROUP BY location_id
ORDER BY total_tasks DESC
LIMIT 10;

-- QUERY 8: Check appointments by source
SELECT
    created_source,
    COUNT(*) as count,
    COUNT(CASE WHEN outcome_status = 'showed' THEN 1 END) as showed,
    COUNT(CASE WHEN outcome_status = 'no_show' THEN 1 END) as no_show,
    COUNT(CASE WHEN outcome_status = 'pending' THEN 1 END) as pending
FROM appointments
GROUP BY created_source;

-- QUERY 9: Check reactivations by action type
SELECT
    action,
    COUNT(*) as count
FROM reactivations
GROUP BY action;

-- QUERY 10: Verify v_dealerships list
SELECT * FROM v_dealerships ORDER BY dealership_name LIMIT 20;
