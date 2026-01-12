-- ============================================
-- FIX v_pipeline_funnel TO SHOW ALL DATA
-- Removes new_inbound filter - shows ALL leads, ALL appointments
-- ============================================

-- Drop and recreate the view
DROP VIEW IF EXISTS v_pipeline_funnel CASCADE;

CREATE OR REPLACE VIEW v_pipeline_funnel AS
WITH lead_stats AS (
    SELECT
        l.location_id,
        COUNT(*) AS total_leads,
        COUNT(*) FILTER (WHERE l.first_outbound_at IS NOT NULL) AS outbound_sent,
        ROUND(AVG(l.speed_to_lead_seconds) FILTER (
            WHERE l.speed_to_lead_seconds IS NOT NULL
            AND l.speed_to_lead_seconds > 0
            AND l.speed_to_lead_seconds <= 600
        ), 0) AS avg_speed_to_lead_seconds,
        COUNT(*) FILTER (
            WHERE l.speed_to_lead_seconds IS NOT NULL
            AND l.speed_to_lead_seconds > 0
            AND l.speed_to_lead_seconds <= 600
        ) AS speed_sample_size,
        COUNT(*) FILTER (WHERE l.first_response_at IS NOT NULL) AS total_responses,
        COUNT(*) FILTER (WHERE l.responded = true) AS responded
    FROM leads l
    GROUP BY l.location_id
),
lead_appointments AS (
    SELECT
        l.location_id,
        COUNT(DISTINCT l.contact_id) AS leads_with_appointments
    FROM leads l
    JOIN appointments a ON l.contact_id = a.contact_id
    GROUP BY l.location_id
),
appointment_stats AS (
    SELECT
        a.location_id,
        COUNT(*) AS total_appointments,
        COUNT(*) FILTER (WHERE a.appointment_time < now()) AS past_appointments,
        COUNT(*) FILTER (WHERE a.appointment_time < now() AND a.outcome_status <> 'pending') AS marked_appointments,
        COUNT(*) FILTER (WHERE a.appointment_time < now() AND a.outcome_status = 'pending') AS unmarked_appointments,
        COUNT(*) FILTER (WHERE a.outcome_status = 'showed') AS showed,
        COUNT(*) FILTER (WHERE a.outcome_status = 'no_show') AS no_shows,
        COUNT(*) FILTER (WHERE a.outcome_status = 'cancelled') AS cancelled
    FROM appointments a
    GROUP BY a.location_id
),
ai_opt_outs AS (
    SELECT
        ad.location_id,
        COUNT(DISTINCT ad.contact_id) AS opt_outs
    FROM ai_decisions ad
    WHERE ad.action = 'remove'
    GROUP BY ad.location_id
),
rep_removes AS (
    SELECT
        r.location_id,
        COUNT(DISTINCT r.contact_id) AS rep_removed
    FROM reactivations r
    WHERE r.action = 'remove'
    GROUP BY r.location_id
)
SELECT
    ls.location_id,
    d.dealership_name,
    -- Lead metrics (ALL leads)
    COALESCE(ls.total_leads, 0) AS total_leads,
    COALESCE(ls.outbound_sent, 0) AS outbound_sent,
    ROUND(100.0 * COALESCE(ls.outbound_sent, 0) / NULLIF(COALESCE(ls.total_leads, 0), 0), 1) AS outbound_rate,
    -- Speed metrics
    COALESCE(ls.avg_speed_to_lead_seconds, 0) AS avg_speed_to_lead_seconds,
    ROUND(COALESCE(ls.avg_speed_to_lead_seconds, 0) / 60.0, 1) AS avg_speed_to_lead_minutes,
    COALESCE(ls.speed_sample_size, 0) AS speed_sample_size,
    -- Response metrics (ALL leads)
    COALESCE(ls.total_responses, 0) AS total_responses,
    COALESCE(ls.responded, 0) AS responded,
    ROUND(100.0 * COALESCE(ls.total_responses, 0) / NULLIF(COALESCE(ls.outbound_sent, 0), 0), 1) AS response_rate,
    -- Opt-outs
    COALESCE(ao.opt_outs, 0) AS opt_outs,
    COALESCE(rr.rep_removed, 0) AS rep_removed,
    -- Appointment metrics (ALL appointments)
    COALESCE(la.leads_with_appointments, 0) AS leads_with_appointments,
    ROUND(100.0 * COALESCE(la.leads_with_appointments, 0) / NULLIF(COALESCE(ls.responded, 0), 0), 1) AS booking_rate,
    COALESCE(ast.total_appointments, 0) AS total_appointments,
    COALESCE(ast.past_appointments, 0) AS past_appointments,
    COALESCE(ast.marked_appointments, 0) AS marked_appointments,
    COALESCE(ast.unmarked_appointments, 0) AS unmarked_appointments,
    COALESCE(ast.showed, 0) AS showed,
    COALESCE(ast.no_shows, 0) AS no_shows,
    COALESCE(ast.cancelled, 0) AS cancelled,
    ROUND(100.0 * COALESCE(ast.showed, 0) / NULLIF(COALESCE(ast.showed, 0) + COALESCE(ast.no_shows, 0), 0), 1) AS show_rate,
    ROUND(100.0 * COALESCE(ast.marked_appointments, 0) / NULLIF(COALESCE(ast.past_appointments, 0), 0), 1) AS marking_rate
FROM lead_stats ls
LEFT JOIN v_dealerships d ON ls.location_id = d.location_id
LEFT JOIN ai_opt_outs ao ON ls.location_id = ao.location_id
LEFT JOIN rep_removes rr ON ls.location_id = rr.location_id
LEFT JOIN lead_appointments la ON ls.location_id = la.location_id
LEFT JOIN appointment_stats ast ON ls.location_id = ast.location_id;

-- Verify the fix
SELECT
    location_id,
    dealership_name,
    total_leads,
    outbound_sent,
    total_responses,
    leads_with_appointments,
    total_appointments,
    past_appointments,
    showed,
    no_shows,
    show_rate
FROM v_pipeline_funnel
WHERE location_id = 'VV8YlH21kFyXfDLuGkfZ';
