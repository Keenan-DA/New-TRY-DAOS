-- ============================================
-- AUTOPLEX APPOINTMENT DATA DIAGNOSTIC
-- Run these to understand the discrepancy
-- ============================================

-- QUERY 1: Find Autoplex's location_id
SELECT location_id, dealership_name
FROM v_dealerships
WHERE dealership_name ILIKE '%autoplex%';

-- QUERY 2: Get raw appointment counts for Autoplex
-- (Replace 'AUTOPLEX_LOCATION_ID' with actual ID from Query 1)
SELECT
    location_id,
    COUNT(*) as total_appointments_all_time,
    COUNT(*) FILTER (WHERE appointment_time < now()) as past_appointments,
    COUNT(*) FILTER (WHERE appointment_time >= now()) as future_appointments,
    COUNT(*) FILTER (WHERE appointment_created_at >= (now() - interval '30 days')) as appointments_last_30,
    COUNT(*) FILTER (WHERE appointment_time < now() AND appointment_created_at >= (now() - interval '30 days')) as past_appointments_last_30
FROM appointments
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'  -- Autoplex's location_id (update if different)
GROUP BY location_id;

-- QUERY 3: Check what v_pipeline_funnel returns for Autoplex
SELECT
    location_id,
    dealership_name,
    total_new_inbound,
    appointments_booked,  -- This is LEADS that have appointments, not total appointments
    total_appointments,
    past_appointments,
    showed,
    no_shows
FROM v_pipeline_funnel
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ';

-- QUERY 4: Check what v_cs_account_health returns for Autoplex
SELECT
    location_id,
    dealership_name,
    appointments_last_30,
    past_appointments,
    showed,
    no_shows,
    unmarked_appointments
FROM v_cs_account_health
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ';

-- QUERY 5: Understand the difference - Leads vs Appointments
-- appointments_booked in pipeline = COUNT of LEADS that have at least 1 appointment
-- total_appointments = COUNT of APPOINTMENTS (a lead can have multiple)
SELECT
    'Unique leads with appointments' as metric,
    COUNT(DISTINCT contact_id) as count
FROM appointments
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'
UNION ALL
SELECT
    'Total appointment records' as metric,
    COUNT(*) as count
FROM appointments
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'
UNION ALL
SELECT
    'Past appointments (before now)' as metric,
    COUNT(*) as count
FROM appointments
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'
AND appointment_time < now()
UNION ALL
SELECT
    'Appointments created in last 30 days' as metric,
    COUNT(*) as count
FROM appointments
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'
AND appointment_created_at >= (now() - interval '30 days');
