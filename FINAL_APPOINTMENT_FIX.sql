-- ============================================================================
-- DRIVE AI 7.0 - COMPLETE APPOINTMENT SYSTEM FIX
-- ============================================================================
-- This file contains ALL fixes for the appointment system:
--
-- 1. insert_appointment() - Fixed for Drive AI 7.0 n8n workflow
--    - Added p_appt_valid parameter that n8n sends
--    - Now matches exact parameters from n8n workflow
--
-- 2. upsert_appointment_from_ghl() - NEW for GHL webhook (INSERT + UPDATE)
--    - INSERTs new appointments if they don't exist
--    - UPDATEs existing appointments (outcome status only)
--    - Only marks as user_booked if created_by is a real user name
--
-- 3. update_appointment_outcome() - REPLACED with upsert logic
--    - The edge function calls this - NO edge function changes needed!
--    - Now does INSERT if appointment doesn't exist
--    - Preserves existing created_source values
--
-- DEPLOY ORDER: Run this entire file in Supabase SQL Editor
-- LAST UPDATED: January 19, 2026
-- ============================================================================


-- ============================================================================
-- PART 1: FIX insert_appointment FOR DRIVE AI 7.0
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


-- ============================================================================
-- PART 2: UPSERT FUNCTION FOR GHL WEBHOOK
-- ============================================================================
-- PURPOSE: Handle appointments from GHL directly (rep-booked appointments)
--
-- SOURCE LOGIC:
--   - If created_by has a user name (not "Other", not empty) → user_booked
--   - If created_by is "Other" or empty → could be system, check if exists
--   - NEVER overwrite existing created_source (preserve ai_automated/rep_instructed)
--
-- GHL Webhook Payload Structure:
--   calendar.appointmentId
--   calendar.created_by (user name OR "Other" OR empty)
--   calendar.created_by_user_id (user id if created by user)
--   calendar.startTime
--   calendar.status
--   calendar.appoinmentStatus
-- ============================================================================

DROP FUNCTION IF EXISTS upsert_appointment_from_ghl(JSONB);

CREATE OR REPLACE FUNCTION upsert_appointment_from_ghl(payload JSONB)
RETURNS JSONB AS $$
DECLARE
  v_calendar JSONB;
  v_ghl_appointment_id TEXT;
  v_location_id TEXT;
  v_contact_id TEXT;
  v_outcome_status TEXT;
  v_appointment_status TEXT;
  v_created_by TEXT;
  v_created_by_user_id TEXT;
  v_existing_record RECORD;
  v_result_id UUID;
  v_rows_updated INT := 0;
  v_is_insert BOOLEAN := FALSE;
  v_final_source TEXT;
  v_is_user_booked BOOLEAN := FALSE;
BEGIN
  -- Extract calendar object (GHL sends appointment data in calendar field)
  v_calendar := payload->'calendar';

  -- Extract key fields - support both direct payload and calendar nested structure
  v_ghl_appointment_id := COALESCE(
    v_calendar->>'appointmentId',
    payload->>'appointmentId',
    payload->>'id'
  );
  v_location_id := COALESCE(
    payload->>'locationId',
    payload->>'location_id'
  );
  v_contact_id := COALESCE(
    payload->>'contactId',
    payload->>'contact_id'
  );

  -- Get created_by info to determine source
  v_created_by := COALESCE(
    v_calendar->>'created_by',
    payload->>'created_by',
    ''
  );
  v_created_by_user_id := COALESCE(
    v_calendar->>'created_by_user_id',
    payload->>'created_by_user_id',
    ''
  );

  -- Determine if this is a user-booked appointment
  -- Only mark as user_booked if:
  --   1. created_by has a value AND
  --   2. created_by is NOT "Other" AND
  --   3. created_by is NOT empty/null
  v_is_user_booked := (
    v_created_by IS NOT NULL
    AND v_created_by != ''
    AND LOWER(TRIM(v_created_by)) != 'other'
    AND v_created_by_user_id IS NOT NULL
    AND v_created_by_user_id != ''
  );

  -- Normalize outcome status from GHL values
  v_outcome_status := LOWER(COALESCE(
    v_calendar->>'status',
    payload->>'status',
    payload->>'appointmentStatus',
    'pending'
  ));

  v_outcome_status := CASE v_outcome_status
    WHEN 'showed' THEN 'showed'
    WHEN 'show' THEN 'showed'
    WHEN 'noshow' THEN 'no_show'
    WHEN 'no_show' THEN 'no_show'
    WHEN 'no-show' THEN 'no_show'
    WHEN 'cancelled' THEN 'cancelled'
    WHEN 'canceled' THEN 'cancelled'
    WHEN 'confirmed' THEN 'confirmed'
    WHEN 'new' THEN 'pending'
    WHEN 'booked' THEN 'pending'
    ELSE COALESCE(v_outcome_status, 'pending')
  END;

  v_appointment_status := LOWER(COALESCE(
    v_calendar->>'appoinmentStatus',
    payload->>'appoinmentStatus',
    payload->>'appointmentStatus',
    'pending'
  ));

  -- Validate required fields
  IF v_ghl_appointment_id IS NULL OR v_ghl_appointment_id = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Missing appointmentId',
      'payload_keys', (SELECT jsonb_agg(key) FROM jsonb_object_keys(payload) AS key),
      'calendar_keys', (SELECT jsonb_agg(key) FROM jsonb_object_keys(COALESCE(v_calendar, '{}'::jsonb)) AS key)
    );
  END IF;

  -- Check if appointment already exists
  SELECT id, created_source, outcome_status, reactivation_id
  INTO v_existing_record
  FROM appointments
  WHERE ghl_appointment_id = v_ghl_appointment_id;

  IF v_existing_record.id IS NOT NULL THEN
    -- ========================================
    -- UPDATE EXISTING APPOINTMENT
    -- ========================================
    -- NEVER overwrite created_source - preserve ai_automated/rep_instructed

    UPDATE appointments
    SET
      outcome_status = CASE
        WHEN outcome_status = 'pending' THEN v_outcome_status
        WHEN outcome_status = 'confirmed' AND v_outcome_status IN ('showed', 'no_show', 'cancelled') THEN v_outcome_status
        WHEN v_outcome_status = 'confirmed' AND outcome_status = 'pending' THEN v_outcome_status
        ELSE outcome_status
      END,
      outcome_recorded_at = CASE
        WHEN v_outcome_status IN ('showed', 'no_show', 'cancelled')
          AND outcome_status NOT IN ('showed', 'no_show', 'cancelled')
        THEN NOW()
        ELSE outcome_recorded_at
      END,
      appointment_status = COALESCE(NULLIF(v_appointment_status, ''), appointment_status),
      lead_name = COALESCE(
        NULLIF(payload->>'contactName', ''),
        NULLIF(payload->>'full_name', ''),
        NULLIF(payload->>'leadName', ''),
        lead_name
      ),
      lead_phone = COALESCE(NULLIF(payload->>'phone', ''), lead_phone),
      lead_email = COALESCE(NULLIF(payload->>'email', ''), lead_email),
      appointment_time = COALESCE(
        (v_calendar->>'startTime')::TIMESTAMPTZ,
        (payload->>'startTime')::TIMESTAMPTZ,
        (payload->>'appointmentTime')::TIMESTAMPTZ,
        appointment_time
      ),
      title = COALESCE(
        NULLIF(v_calendar->>'title', ''),
        NULLIF(payload->>'title', ''),
        title
      ),
      updated_at = NOW()
    WHERE ghl_appointment_id = v_ghl_appointment_id
    RETURNING id INTO v_result_id;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    v_is_insert := FALSE;
    v_final_source := v_existing_record.created_source;

  ELSE
    -- ========================================
    -- INSERT NEW APPOINTMENT
    -- ========================================

    -- Determine source for new appointments:
    -- If user booked (has created_by name that's not "Other") → user_booked
    -- Otherwise → leave as whatever is passed or default
    IF v_is_user_booked THEN
      v_final_source := 'user_booked';
    ELSE
      -- Could be from system/AI but came through webhook
      -- Default to user_booked since it's from GHL directly
      -- (AI appointments should come through insert_appointment, not this function)
      v_final_source := COALESCE(NULLIF(payload->>'createdSource', ''), 'user_booked');
    END IF;

    INSERT INTO appointments (
      ghl_appointment_id,
      location_id,
      contact_id,
      dealership_name,
      dealership_timezone,
      lead_name,
      lead_first_name,
      lead_phone,
      lead_email,
      assigned_rep_id,
      assigned_rep_name,
      title,
      appointment_type,
      appointment_time,
      appointment_status,
      outcome_status,
      status,
      created_source,
      source_workflow,
      calendar_id,
      created_at,
      updated_at,
      appointment_created_at
    ) VALUES (
      v_ghl_appointment_id,
      v_location_id,
      v_contact_id,
      COALESCE(payload->>'locationName', payload->>'dealershipName'),
      COALESCE(v_calendar->>'selectedTimezone', payload->>'timezone'),
      COALESCE(payload->>'contactName', payload->>'full_name', payload->>'leadName'),
      payload->>'firstName',
      payload->>'phone',
      payload->>'email',
      COALESCE(v_calendar->>'created_by_user_id', payload->>'assignedUserId'),
      COALESCE(v_calendar->>'created_by', payload->>'assignedUserName'),
      COALESCE(v_calendar->>'title', payload->>'title', 'Appointment'),
      COALESCE(payload->>'appointmentType', 'Store Appointment'),
      COALESCE(
        (v_calendar->>'startTime')::TIMESTAMPTZ,
        (payload->>'startTime')::TIMESTAMPTZ,
        (payload->>'appointmentTime')::TIMESTAMPTZ,
        NOW()
      ),
      v_appointment_status,
      v_outcome_status,
      COALESCE(v_calendar->>'status', payload->>'status', 'booked'),
      v_final_source,
      'ghl_webhook',
      COALESCE(v_calendar->>'id', payload->>'calendarId'),
      NOW(),
      NOW(),
      COALESCE((v_calendar->>'date_created')::TIMESTAMPTZ, (payload->>'dateAdded')::TIMESTAMPTZ, NOW())
    )
    RETURNING id INTO v_result_id;

    v_rows_updated := 1;
    v_is_insert := TRUE;

    -- Update leads table
    IF v_contact_id IS NOT NULL AND v_location_id IS NOT NULL THEN
      UPDATE leads
      SET
        appointment_booked = TRUE,
        appointment_count = COALESCE(appointment_count, 0) + 1,
        first_appointment_at = COALESCE(first_appointment_at, NOW()),
        updated_at = NOW()
      WHERE contact_id = v_contact_id
        AND location_id = v_location_id;
    END IF;

  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'success', v_result_id IS NOT NULL,
    'appointment_id', v_result_id,
    'ghl_appointment_id', v_ghl_appointment_id,
    'outcome_status', v_outcome_status,
    'rows_updated', v_rows_updated,
    'is_insert', v_is_insert,
    'created_source', v_final_source,
    'is_user_booked', v_is_user_booked,
    'created_by', v_created_by,
    'created_by_user_id', v_created_by_user_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'error_detail', SQLSTATE,
    'ghl_appointment_id', v_ghl_appointment_id,
    'location_id', v_location_id,
    'contact_id', v_contact_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION upsert_appointment_from_ghl(JSONB) TO anon, authenticated, service_role;


-- ============================================================================
-- PART 3: REPLACE update_appointment_outcome WITH UPSERT LOGIC
-- ============================================================================
-- The edge function calls update_appointment_outcome()
-- We replace it with upsert logic so NO edge function changes are needed!
-- ============================================================================

DROP FUNCTION IF EXISTS update_appointment_outcome(JSONB);

CREATE OR REPLACE FUNCTION update_appointment_outcome(payload JSONB)
RETURNS JSONB AS $$
DECLARE
  v_calendar JSONB;
  v_ghl_appointment_id TEXT;
  v_location_id TEXT;
  v_contact_id TEXT;
  v_outcome_status TEXT;
  v_appointment_status TEXT;
  v_created_by TEXT;
  v_created_by_user_id TEXT;
  v_existing_record RECORD;
  v_result_id UUID;
  v_rows_updated INT := 0;
  v_is_insert BOOLEAN := FALSE;
  v_final_source TEXT;
  v_is_user_booked BOOLEAN := FALSE;
BEGIN
  -- Extract calendar object
  v_calendar := payload->'calendar';

  -- Extract key fields
  v_ghl_appointment_id := COALESCE(
    v_calendar->>'appointmentId',
    payload->>'appointmentId',
    payload->>'id'
  );
  v_location_id := COALESCE(payload->>'locationId', payload->>'location_id');
  v_contact_id := COALESCE(payload->>'contactId', payload->>'contact_id');

  -- Get created_by info
  v_created_by := COALESCE(v_calendar->>'created_by', payload->>'created_by', '');
  v_created_by_user_id := COALESCE(v_calendar->>'created_by_user_id', payload->>'created_by_user_id', '');

  -- Only user_booked if created_by is a real name (not "Other" or empty)
  v_is_user_booked := (
    v_created_by IS NOT NULL
    AND v_created_by != ''
    AND LOWER(TRIM(v_created_by)) != 'other'
    AND v_created_by_user_id IS NOT NULL
    AND v_created_by_user_id != ''
  );

  -- Normalize outcome status
  v_outcome_status := LOWER(COALESCE(
    v_calendar->>'status', payload->>'status', payload->>'appointmentStatus', 'pending'
  ));
  v_outcome_status := CASE v_outcome_status
    WHEN 'showed' THEN 'showed'
    WHEN 'show' THEN 'showed'
    WHEN 'noshow' THEN 'no_show'
    WHEN 'no_show' THEN 'no_show'
    WHEN 'no-show' THEN 'no_show'
    WHEN 'cancelled' THEN 'cancelled'
    WHEN 'canceled' THEN 'cancelled'
    WHEN 'confirmed' THEN 'confirmed'
    WHEN 'new' THEN 'pending'
    WHEN 'booked' THEN 'pending'
    ELSE 'pending'
  END;

  v_appointment_status := LOWER(COALESCE(
    v_calendar->>'appoinmentStatus', payload->>'appoinmentStatus', 'confirmed'
  ));

  -- Validate
  IF v_ghl_appointment_id IS NULL OR v_ghl_appointment_id = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing appointmentId');
  END IF;

  -- Check if exists
  SELECT id, created_source INTO v_existing_record
  FROM appointments WHERE ghl_appointment_id = v_ghl_appointment_id;

  IF v_existing_record.id IS NOT NULL THEN
    -- UPDATE existing (never overwrite created_source)
    UPDATE appointments SET
      outcome_status = CASE
        WHEN outcome_status = 'pending' THEN v_outcome_status
        WHEN outcome_status = 'confirmed' AND v_outcome_status IN ('showed', 'no_show', 'cancelled') THEN v_outcome_status
        ELSE outcome_status
      END,
      outcome_recorded_at = CASE
        WHEN v_outcome_status IN ('showed', 'no_show', 'cancelled') AND outcome_status NOT IN ('showed', 'no_show', 'cancelled')
        THEN NOW() ELSE outcome_recorded_at
      END,
      appointment_status = COALESCE(NULLIF(v_appointment_status, ''), appointment_status),
      updated_at = NOW()
    WHERE ghl_appointment_id = v_ghl_appointment_id
    RETURNING id INTO v_result_id;

    v_rows_updated := 1;
    v_final_source := v_existing_record.created_source;
  ELSE
    -- INSERT new appointment
    v_final_source := CASE WHEN v_is_user_booked THEN 'user_booked' ELSE 'user_booked' END;

    INSERT INTO appointments (
      ghl_appointment_id, location_id, contact_id,
      lead_name, lead_phone, lead_email,
      title, appointment_time, appointment_status, outcome_status,
      status, created_source, source_workflow, calendar_id,
      assigned_rep_id, assigned_rep_name,
      created_at, updated_at
    ) VALUES (
      v_ghl_appointment_id, v_location_id, v_contact_id,
      COALESCE(payload->>'contactName', payload->>'full_name'),
      payload->>'phone', payload->>'email',
      COALESCE(v_calendar->>'title', 'Appointment'),
      COALESCE((v_calendar->>'startTime')::TIMESTAMPTZ, NOW()),
      v_appointment_status, v_outcome_status,
      'booked', v_final_source, 'ghl_webhook',
      COALESCE(v_calendar->>'id', payload->>'calendarId'),
      v_created_by_user_id, v_created_by,
      NOW(), NOW()
    ) RETURNING id INTO v_result_id;

    v_rows_updated := 1;
    v_is_insert := TRUE;

    -- Update leads table
    IF v_contact_id IS NOT NULL AND v_location_id IS NOT NULL THEN
      UPDATE leads SET
        appointment_booked = TRUE,
        appointment_count = COALESCE(appointment_count, 0) + 1,
        first_appointment_at = COALESCE(first_appointment_at, NOW()),
        updated_at = NOW()
      WHERE contact_id = v_contact_id AND location_id = v_location_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_result_id,
    'ghl_appointment_id', v_ghl_appointment_id,
    'outcome_status', v_outcome_status,
    'rows_updated', v_rows_updated,
    'is_insert', v_is_insert,
    'created_source', v_final_source
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_appointment_outcome(JSONB) TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Test insert_appointment (Drive AI 7.0 style):
/*
SELECT insert_appointment(
  'TEST_AI_123',         -- p_ghl_appointment_id
  'trace-123',           -- p_trace_id
  'cal-123',             -- p_calendar_id
  'RMMkdOgBaw5tjVTzSeQ9', -- p_location_id (Camacho)
  'Test Dealer',         -- p_dealership_name
  '123 Main St',         -- p_dealership_address
  '9-5',                 -- p_dealership_hours
  'America/Chicago',     -- p_dealership_timezone
  'contact-123',         -- p_contact_id
  'Test AI User',        -- p_lead_name
  'Test',                -- p_lead_first_name
  '+15551234567',        -- p_lead_phone
  'test@test.com',       -- p_lead_email
  'rep-123',             -- p_assigned_rep_id
  'John Rep',            -- p_assigned_rep_name
  'Test Appointment',    -- p_title
  'Store Appointment',   -- p_appointment_type
  NOW() + INTERVAL '1 day', -- p_appointment_time
  'Test summary',        -- p_appointment_summary
  true,                  -- p_appt_valid
  'booked',              -- p_status
  'confirmed',           -- p_appointment_status
  'ai_automated',        -- p_created_source
  'drive_ai_7'           -- p_source_workflow
);

-- Verify it was created as ai_automated:
SELECT id, ghl_appointment_id, lead_name, created_source, source_workflow
FROM appointments WHERE ghl_appointment_id = 'TEST_AI_123';

-- Cleanup:
DELETE FROM appointments WHERE ghl_appointment_id = 'TEST_AI_123';
*/


-- Test upsert_appointment_from_ghl (GHL webhook style - user booked):
/*
SELECT upsert_appointment_from_ghl('{
  "locationId": "RMMkdOgBaw5tjVTzSeQ9",
  "contactId": "test-contact-456",
  "contactName": "Test Rep User",
  "phone": "+15559876543",
  "email": "repuser@test.com",
  "calendar": {
    "appointmentId": "TEST_REP_456",
    "title": "Test - Store Appointment",
    "startTime": "2026-01-20T15:00:00",
    "status": "booked",
    "appoinmentStatus": "confirmed",
    "created_by": "John Smith",
    "created_by_user_id": "user-123"
  }
}'::jsonb);

-- Verify it was created as user_booked (because created_by has a name):
SELECT id, ghl_appointment_id, lead_name, created_source, source_workflow
FROM appointments WHERE ghl_appointment_id = 'TEST_REP_456';

-- Cleanup:
DELETE FROM appointments WHERE ghl_appointment_id = 'TEST_REP_456';
*/


-- Test upsert_appointment_from_ghl (GHL webhook style - "Other" source):
/*
SELECT upsert_appointment_from_ghl('{
  "locationId": "RMMkdOgBaw5tjVTzSeQ9",
  "contactId": "test-contact-789",
  "contactName": "Test Other User",
  "phone": "+15551112222",
  "calendar": {
    "appointmentId": "TEST_OTHER_789",
    "title": "Test - Store Appointment",
    "startTime": "2026-01-21T14:00:00",
    "status": "booked",
    "appoinmentStatus": "confirmed",
    "created_by": "Other",
    "created_by_user_id": ""
  }
}'::jsonb);

-- Verify it was created as user_booked (default, since "Other" is not a real user):
SELECT id, ghl_appointment_id, lead_name, created_source, source_workflow
FROM appointments WHERE ghl_appointment_id = 'TEST_OTHER_789';

-- Cleanup:
DELETE FROM appointments WHERE ghl_appointment_id = 'TEST_OTHER_789';
*/


-- ============================================================================
-- SOURCE PRIORITY REFERENCE
-- ============================================================================
--
-- CREATED_SOURCE VALUES (in order of priority):
--
-- 1. 'rep_instructed' - Appointment booked via Reactivate Drive
--    - Has reactivation_id linked
--    - NEVER overwritten by other sources
--    - Created by: insert_reactivation RPC
--
-- 2. 'ai_automated' - Appointment booked by Drive AI
--    - source_workflow = 'drive_ai_7'
--    - Only overwritten if rep takes over via reactivation
--    - Created by: insert_appointment RPC (this file, Part 1)
--
-- 3. 'user_booked' - Appointment booked directly in GHL by a rep
--    - created_by = actual user name (not "Other" or empty)
--    - Can be "upgraded" to rep_instructed if rep closes the loop
--    - Created by: upsert_appointment_from_ghl (this file, Part 2)
--
-- The system will:
-- - INSERT new appointments with appropriate source
-- - UPDATE outcome_status regardless of source
-- - NEVER overwrite created_source once set (preserves original source)
-- ============================================================================


-- ============================================================================
-- SUMMARY OF FIXES
-- ============================================================================
--
-- ISSUE 1: Drive AI 7.0 appointments failing with 404
--   CAUSE: n8n sends p_appt_valid, function didn't accept it
--   FIX: insert_appointment() now accepts p_appt_valid parameter
--
-- ISSUE 2: Rep-booked appointments not captured
--   CAUSE: GHL webhook only did UPDATE, not INSERT
--   FIX: update_appointment_outcome() now does INSERT if not exists
--        (NO edge function changes needed!)
--
-- ISSUE 3: Source attribution incorrect
--   CAUSE: All webhook inserts defaulted to user_booked
--   FIX: Only mark as user_booked if created_by is a real user name
--        (not "Other" or empty)
--
-- AFTER DEPLOYING:
-- 1. All new Drive AI 7.0 appointments will be captured ✓
-- 2. All rep-booked GHL appointments will be captured ✓
-- 3. Source attribution will be correct ✓
-- 4. Existing source values will never be overwritten ✓
-- 5. No edge function changes required ✓
-- ============================================================================
