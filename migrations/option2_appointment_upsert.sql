-- ============================================================================
-- OPTION 2: APPOINTMENT UPSERT LOGIC
-- ============================================================================
-- Purpose: Ensure correct created_source regardless of which system fires first
--
-- Logic:
--   - GHL Webhook: INSERT ... ON CONFLICT DO NOTHING (passive)
--   - n8n Workflows: INSERT ... ON CONFLICT DO UPDATE (authoritative)
--
-- Result: n8n always wins, even if webhook fires first
-- ============================================================================

-- ============================================================================
-- STEP 1: Ensure unique constraint on ghl_appointment_id
-- ============================================================================

-- Check if constraint exists, if not create it
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'appointments_ghl_appointment_id_key'
    ) THEN
        ALTER TABLE appointments
        ADD CONSTRAINT appointments_ghl_appointment_id_key
        UNIQUE (ghl_appointment_id);
        RAISE NOTICE 'Created unique constraint on ghl_appointment_id';
    ELSE
        RAISE NOTICE 'Unique constraint already exists';
    END IF;
END $$;


-- ============================================================================
-- STEP 2: Update insert_appointment() - Used by n8n (AUTHORITATIVE)
-- ============================================================================
-- This function is called by Drive AI 7.0 and Reactivate Drive workflows
-- It uses ON CONFLICT DO UPDATE to OVERRIDE if webhook inserted first

-- First, drop ALL existing versions of insert_appointment function
DO $$
DECLARE
    func_oid oid;
BEGIN
    FOR func_oid IN
        SELECT p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE p.proname = 'insert_appointment'
        AND n.nspname = 'public'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || func_oid::regprocedure || ' CASCADE';
    END LOOP;
END $$;

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
    p_lead_type TEXT DEFAULT NULL,
    p_assigned_rep_id TEXT DEFAULT NULL,
    p_assigned_rep_name TEXT DEFAULT NULL,
    p_title TEXT DEFAULT NULL,
    p_appointment_type TEXT DEFAULT NULL,
    p_appointment_time TIMESTAMPTZ DEFAULT NULL,
    p_appointment_summary TEXT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_appointment_status TEXT DEFAULT NULL,
    p_created_source TEXT DEFAULT NULL,  -- 'ai_automated' or 'rep_instructed'
    p_source_workflow TEXT DEFAULT NULL,
    p_reactivation_id UUID DEFAULT NULL,
    p_raw_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_appointment_id UUID;
BEGIN
    -- UPSERT: Insert new OR update if webhook got there first
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
        lead_type,
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
        reactivation_id,
        raw_data,
        appointment_created_at,
        created_at,
        updated_at
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
        p_lead_type,
        p_assigned_rep_id,
        p_assigned_rep_name,
        p_title,
        p_appointment_type,
        p_appointment_time,
        p_appointment_summary,
        p_status,
        p_appointment_status,
        'pending',  -- Default outcome
        p_created_source,
        p_source_workflow,
        p_reactivation_id,
        p_raw_data,
        NOW(),
        NOW(),
        NOW()
    )
    ON CONFLICT (ghl_appointment_id)
    DO UPDATE SET
        -- n8n is authoritative - OVERRIDE these fields
        created_source = EXCLUDED.created_source,
        source_workflow = EXCLUDED.source_workflow,
        reactivation_id = COALESCE(EXCLUDED.reactivation_id, appointments.reactivation_id),
        trace_id = COALESCE(EXCLUDED.trace_id, appointments.trace_id),
        -- Update other fields only if provided (don't overwrite with NULLs)
        calendar_id = COALESCE(EXCLUDED.calendar_id, appointments.calendar_id),
        dealership_name = COALESCE(EXCLUDED.dealership_name, appointments.dealership_name),
        dealership_address = COALESCE(EXCLUDED.dealership_address, appointments.dealership_address),
        dealership_hours = COALESCE(EXCLUDED.dealership_hours, appointments.dealership_hours),
        dealership_timezone = COALESCE(EXCLUDED.dealership_timezone, appointments.dealership_timezone),
        lead_name = COALESCE(EXCLUDED.lead_name, appointments.lead_name),
        lead_first_name = COALESCE(EXCLUDED.lead_first_name, appointments.lead_first_name),
        lead_phone = COALESCE(EXCLUDED.lead_phone, appointments.lead_phone),
        lead_email = COALESCE(EXCLUDED.lead_email, appointments.lead_email),
        lead_type = COALESCE(EXCLUDED.lead_type, appointments.lead_type),
        assigned_rep_id = COALESCE(EXCLUDED.assigned_rep_id, appointments.assigned_rep_id),
        assigned_rep_name = COALESCE(EXCLUDED.assigned_rep_name, appointments.assigned_rep_name),
        title = COALESCE(EXCLUDED.title, appointments.title),
        appointment_type = COALESCE(EXCLUDED.appointment_type, appointments.appointment_type),
        appointment_time = COALESCE(EXCLUDED.appointment_time, appointments.appointment_time),
        appointment_summary = COALESCE(EXCLUDED.appointment_summary, appointments.appointment_summary),
        raw_data = COALESCE(EXCLUDED.raw_data, appointments.raw_data),
        updated_at = NOW()
    RETURNING id INTO v_appointment_id;

    RETURN v_appointment_id;
END;
$$;

COMMENT ON FUNCTION insert_appointment IS
'Authoritative appointment insert from n8n workflows (Drive AI 7.0, Reactivate Drive).
Uses ON CONFLICT DO UPDATE to override if GHL webhook inserted first.
created_source should be ai_automated or rep_instructed.';


-- ============================================================================
-- STEP 3: Create upsert_appointment_from_webhook() - Used by GHL Webhook (PASSIVE)
-- ============================================================================
-- This function is called by the GHL "Appointment Created" webhook
-- It uses ON CONFLICT DO NOTHING to defer to n8n if it already inserted

CREATE OR REPLACE FUNCTION upsert_appointment_from_webhook(
    p_ghl_appointment_id TEXT,
    p_location_id TEXT,
    p_contact_id TEXT,
    p_calendar_id TEXT DEFAULT NULL,
    p_assigned_rep_id TEXT DEFAULT NULL,
    p_assigned_rep_name TEXT DEFAULT NULL,
    p_title TEXT DEFAULT NULL,
    p_appointment_type TEXT DEFAULT NULL,
    p_appointment_time TIMESTAMPTZ DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_appointment_status TEXT DEFAULT NULL,
    p_created_by_user_id TEXT DEFAULT NULL,  -- GHL user who created it
    p_created_by_user_name TEXT DEFAULT NULL,
    p_booking_source TEXT DEFAULT NULL,       -- 'ghl_calendar', 'workflow', etc.
    p_raw_data JSONB DEFAULT NULL
)
RETURNS TABLE (
    appointment_id UUID,
    action_taken TEXT,
    created_source TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_appointment_id UUID;
    v_action TEXT;
    v_source TEXT;
    v_existing_source TEXT;
    v_lead_info RECORD;
BEGIN
    -- Check if appointment already exists
    SELECT id, created_source INTO v_appointment_id, v_existing_source
    FROM appointments
    WHERE ghl_appointment_id = p_ghl_appointment_id;

    IF v_appointment_id IS NOT NULL THEN
        -- Appointment already exists (n8n got there first)
        -- DO NOTHING - respect the authoritative source
        v_action := 'skipped_existing';
        v_source := v_existing_source;
    ELSE
        -- New appointment - this is a manual creation in GHL
        v_source := 'rep_manual';

        -- Get lead info for denormalization
        SELECT
            l.lead_name,
            l.lead_phone,
            l.lead_email,
            l.lead_type,
            d.dealership_name,
            d.dealership_timezone
        INTO v_lead_info
        FROM leads l
        LEFT JOIN v_dealerships d ON l.location_id = d.location_id
        WHERE l.contact_id = p_contact_id;

        INSERT INTO appointments (
            ghl_appointment_id,
            location_id,
            contact_id,
            calendar_id,
            lead_name,
            lead_phone,
            lead_email,
            lead_type,
            dealership_name,
            dealership_timezone,
            assigned_rep_id,
            assigned_rep_name,
            title,
            appointment_type,
            appointment_time,
            status,
            appointment_status,
            outcome_status,
            created_source,
            source_workflow,
            raw_data,
            appointment_created_at,
            created_at,
            updated_at
        ) VALUES (
            p_ghl_appointment_id,
            p_location_id,
            p_contact_id,
            p_calendar_id,
            v_lead_info.lead_name,
            v_lead_info.lead_phone,
            v_lead_info.lead_email,
            v_lead_info.lead_type,
            v_lead_info.dealership_name,
            v_lead_info.dealership_timezone,
            p_assigned_rep_id,
            p_assigned_rep_name,
            p_title,
            p_appointment_type,
            p_appointment_time,
            p_status,
            p_appointment_status,
            'pending',
            'rep_manual',        -- Manual creation in GHL
            'ghl_calendar',      -- Source is GHL calendar
            p_raw_data,
            NOW(),
            NOW(),
            NOW()
        )
        RETURNING id INTO v_appointment_id;

        v_action := 'inserted_new';
    END IF;

    RETURN QUERY SELECT v_appointment_id, v_action, v_source;
END;
$$;

COMMENT ON FUNCTION upsert_appointment_from_webhook IS
'Passive appointment insert from GHL webhook.
If appointment already exists (from n8n), does nothing.
If new, inserts with created_source = rep_manual.
Returns action_taken: skipped_existing or inserted_new.';


-- ============================================================================
-- STEP 4: Update views to include 'rep_manual' in human counts
-- ============================================================================

-- v_appointment_stats: Add rep_manual to human counts
CREATE OR REPLACE VIEW v_appointment_stats AS
SELECT
    d.location_id,
    d.dealership_name,
    -- Total appointments
    COUNT(a.id) as total_appointments,

    -- By source (3 categories now)
    COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated') as ai_booked,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_instructed') as rep_instructed,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_manual') as rep_manual,

    -- Combined human count (rep_instructed + rep_manual)
    COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) as human_booked,

    -- By outcome
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'showed') as showed,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show') as no_shows,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'cancelled') as cancelled,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'pending' AND a.appointment_time >= NOW()) as pending,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'pending' AND a.appointment_time < NOW()) as unmarked,

    -- Show rate (showed / (showed + no_show))
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.outcome_status IN ('showed', 'no_show')) = 0 THEN NULL
        ELSE ROUND(
            COUNT(a.id) FILTER (WHERE a.outcome_status = 'showed')::numeric /
            COUNT(a.id) FILTER (WHERE a.outcome_status IN ('showed', 'no_show')) * 100, 1
        )
    END as show_rate,

    -- Marking percentage
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()) = 0 THEN NULL
        ELSE ROUND(
            COUNT(a.id) FILTER (WHERE a.outcome_status != 'pending' AND a.appointment_time < NOW())::numeric /
            COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()) * 100, 1
        )
    END as marking_pct,

    -- No-show recovery
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show' AND a.follow_up_after_outcome IS NOT NULL) as no_shows_worked,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show' AND a.follow_up_after_outcome IS NULL) as no_shows_unworked,
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show') = 0 THEN NULL
        ELSE ROUND(
            COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show' AND a.recovery_reactivation_id IS NOT NULL)::numeric /
            COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show') * 100, 1
        )
    END as no_show_recovery_pct

FROM v_dealerships d
LEFT JOIN appointments a ON d.location_id = a.location_id
GROUP BY d.location_id, d.dealership_name;

COMMENT ON VIEW v_appointment_stats IS
'Appointment metrics by dealership.
human_booked = rep_instructed + rep_manual (both count as human-created).';


-- v_ai_human_ratio: Include rep_manual in human side
CREATE OR REPLACE VIEW v_ai_human_ratio AS
SELECT
    d.location_id,
    d.dealership_name,

    -- AI appointments
    COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated') as ai_booked,

    -- Human appointments (rep_instructed + rep_manual)
    COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) as human_booked,

    -- Breakdown of human
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_instructed') as rep_instructed,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_manual') as rep_manual,

    -- Ratio: AI / Human
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) = 0 THEN NULL
        ELSE ROUND(
            COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated')::numeric /
            COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')), 2
        )
    END as ai_human_ratio,

    -- Status based on ratio
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) = 0 THEN 'NO_HUMAN_DATA'
        WHEN COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated')::numeric /
             COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) < 0.5 THEN 'AI_UNDERUTILIZED'
        WHEN COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated')::numeric /
             COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) BETWEEN 0.8 AND 1.2 THEN 'BALANCED'
        WHEN COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated')::numeric /
             COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) > 2.0 THEN 'STAFF_UNDERPERFORMING'
        ELSE 'OK'
    END as balance_status

FROM v_dealerships d
LEFT JOIN appointments a ON d.location_id = a.location_id
GROUP BY d.location_id, d.dealership_name;

COMMENT ON VIEW v_ai_human_ratio IS
'AI vs Human appointment ratio.
Human = rep_instructed (via Reactivate Drive) + rep_manual (direct GHL booking).
BALANCED = 0.8-1.2 ratio, AI_UNDERUTILIZED < 0.5, STAFF_UNDERPERFORMING > 2.0';


-- v_rep_appointment_breakdown: Include rep_manual
CREATE OR REPLACE VIEW v_rep_appointment_breakdown AS
SELECT
    a.location_id,
    a.assigned_rep_id,
    COALESCE(a.assigned_rep_name, 'Unassigned') as rep_name,
    d.dealership_name,

    -- Total appointments
    COUNT(a.id) as total_appointments,

    -- By source
    COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated') as ai_booked,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_instructed') as rep_instructed,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_manual') as rep_manual,
    COUNT(a.id) FILTER (WHERE a.created_source IN ('rep_instructed', 'rep_manual')) as human_booked,

    -- Past appointments (for marking rate)
    COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()) as past_appointments,
    COUNT(a.id) FILTER (WHERE a.appointment_time < NOW() AND a.outcome_status != 'pending') as marked_appointments,
    COUNT(a.id) FILTER (WHERE a.appointment_time < NOW() AND a.outcome_status = 'pending') as unmarked_appointments,

    -- Marking rate
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()) = 0 THEN NULL
        ELSE ROUND(
            COUNT(a.id) FILTER (WHERE a.appointment_time < NOW() AND a.outcome_status != 'pending')::numeric /
            COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()) * 100, 1
        )
    END as marking_rate,

    -- Outcomes
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'showed') as showed,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'no_show') as no_shows,
    COUNT(a.id) FILTER (WHERE a.outcome_status = 'cancelled') as cancelled,

    -- Show rate
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.outcome_status IN ('showed', 'no_show')) = 0 THEN NULL
        ELSE ROUND(
            COUNT(a.id) FILTER (WHERE a.outcome_status = 'showed')::numeric /
            COUNT(a.id) FILTER (WHERE a.outcome_status IN ('showed', 'no_show')) * 100, 1
        )
    END as show_rate,

    -- Status
    CASE
        WHEN COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()) = 0 THEN 'NO_PAST_APPTS'
        WHEN COUNT(a.id) FILTER (WHERE a.appointment_time < NOW() AND a.outcome_status != 'pending')::numeric /
             NULLIF(COUNT(a.id) FILTER (WHERE a.appointment_time < NOW()), 0) < 0.5 THEN 'LOW_MARKING'
        WHEN COUNT(a.id) FILTER (WHERE a.outcome_status = 'showed')::numeric /
             NULLIF(COUNT(a.id) FILTER (WHERE a.outcome_status IN ('showed', 'no_show')), 0) < 0.5 THEN 'LOW_SHOW_RATE'
        ELSE 'OK'
    END as status

FROM appointments a
LEFT JOIN v_dealerships d ON a.location_id = d.location_id
GROUP BY a.location_id, a.assigned_rep_id, a.assigned_rep_name, d.dealership_name;

COMMENT ON VIEW v_rep_appointment_breakdown IS
'Per-rep appointment metrics.
human_booked = rep_instructed + rep_manual for accurate human attribution.';


-- ============================================================================
-- STEP 5: Verification query
-- ============================================================================
-- Run this after migration to verify the changes

/*
-- Check created_source distribution
SELECT
    created_source,
    COUNT(*) as count
FROM appointments
GROUP BY created_source
ORDER BY count DESC;

-- Verify views work
SELECT * FROM v_ai_human_ratio LIMIT 5;
SELECT * FROM v_appointment_stats LIMIT 5;

-- Test the new webhook function
SELECT * FROM upsert_appointment_from_webhook(
    'test_appt_123',
    'test_location',
    'test_contact'
);
*/


-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Next steps:
-- 1. Run this migration in Supabase SQL Editor
-- 2. Set up GHL webhook for "Appointment Created" → edge function
-- 3. Edge function calls upsert_appointment_from_webhook()
-- 4. n8n workflows continue using insert_appointment() (no changes needed)
-- ============================================================================
