-- ============================================
-- VALIDATE SUPABASE DATA vs GHL EXPORT
-- Date Range: Jan 1-10, 2026
-- ============================================

-- QUERY 1: Compare key accounts (Autoplex, 518 Auto Sales, Clawson)
-- GHL Export shows for Jan 1-10:
--   Autoplex (VV8YlH21kFyXfDLuGkfZ): Contacts=3824, Appointments=144
--   518 Auto Sales (lo3qhbGEZNRLheKkQoiQ): Contacts=382, Appointments=53
--   Clawson Motorsports (0ogMPcTXOM6dezCDbNfa): Contacts=239, Appointments=19

SELECT
    d.dealership_name,
    d.location_id,
    -- LEADS: Count leads created Jan 1-10, 2026
    (SELECT COUNT(*) FROM leads l
     WHERE l.location_id = d.location_id
     AND l.created_at >= '2026-01-01' AND l.created_at < '2026-01-11') as leads_jan1_10,
    -- LEADS: Total all time
    (SELECT COUNT(*) FROM leads l WHERE l.location_id = d.location_id) as leads_all_time,
    -- APPOINTMENTS: Count appointments created Jan 1-10, 2026
    (SELECT COUNT(*) FROM appointments a
     WHERE a.location_id = d.location_id
     AND a.appointment_created_at >= '2026-01-01' AND a.appointment_created_at < '2026-01-11') as appts_jan1_10,
    -- APPOINTMENTS: Total all time
    (SELECT COUNT(*) FROM appointments a WHERE a.location_id = d.location_id) as appts_all_time
FROM v_dealerships d
WHERE d.location_id IN (
    'VV8YlH21kFyXfDLuGkfZ',  -- Autoplex
    'lo3qhbGEZNRLheKkQoiQ',  -- 518 Auto Sales
    '0ogMPcTXOM6dezCDbNfa'   -- Clawson Motorsports
)
ORDER BY d.dealership_name;

-- QUERY 2: Full comparison for ALL accounts (Jan 1-10, 2026)
-- This gives you data to compare against the entire CSV export
SELECT
    d.location_id,
    d.dealership_name,
    COALESCE(l.lead_count, 0) as contacts_supabase,
    COALESCE(a.appt_count, 0) as appointments_supabase
FROM v_dealerships d
LEFT JOIN (
    SELECT location_id, COUNT(*) as lead_count
    FROM leads
    WHERE created_at >= '2026-01-01' AND created_at < '2026-01-11'
    GROUP BY location_id
) l ON d.location_id = l.location_id
LEFT JOIN (
    SELECT location_id, COUNT(*) as appt_count
    FROM appointments
    WHERE appointment_created_at >= '2026-01-01' AND appointment_created_at < '2026-01-11'
    GROUP BY location_id
) a ON d.location_id = a.location_id
ORDER BY d.dealership_name;

-- QUERY 3: Check date ranges in your data
-- See what date range your Supabase data actually covers
SELECT
    'leads' as table_name,
    MIN(created_at) as earliest,
    MAX(created_at) as latest,
    COUNT(*) as total_records
FROM leads
UNION ALL
SELECT
    'appointments',
    MIN(appointment_created_at),
    MAX(appointment_created_at),
    COUNT(*)
FROM appointments
UNION ALL
SELECT
    'tasks',
    MIN(created_at),
    MAX(created_at),
    COUNT(*)
FROM tasks
UNION ALL
SELECT
    'reactivations',
    MIN(reactivated_at),
    MAX(reactivated_at),
    COUNT(*)
FROM reactivations;

-- QUERY 4: Specific check for Autoplex
-- GHL says: Contacts=3824, Appointments=144 for Jan 1-10
SELECT
    'Autoplex Check' as account,
    (SELECT COUNT(*) FROM leads WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'
     AND created_at >= '2026-01-01' AND created_at < '2026-01-11') as leads_jan1_10,
    3824 as ghl_contacts,
    (SELECT COUNT(*) FROM appointments WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ'
     AND appointment_created_at >= '2026-01-01' AND appointment_created_at < '2026-01-11') as appts_jan1_10,
    144 as ghl_appointments;
