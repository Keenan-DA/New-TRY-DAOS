-- ============================================================================
-- DRIVE AI 7.0 - INSERT APPOINTMENT FUNCTION FIX
-- ============================================================================
-- PROBLEM: n8n sends parameters that don't match the Supabase function signature
--
-- n8n sends: p_appt_valid (boolean)
-- Function expects: p_lead_type, p_raw_data, p_reactivation_id (which n8n doesn't send)
--
-- SOLUTION: Create function with EXACT parameters n8n is sending
-- ============================================================================

-- Drop the existing function to replace it
DROP FUNCTION IF EXISTS insert_appointment(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  JSONB, UUID
);

DROP FUNCTION IF EXISTS insert_appointment(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, BOOLEAN, TEXT, TEXT, TEXT, TEXT
);

-- ============================================================================
-- NEW FUNCTION - Matches EXACTLY what n8n Drive AI 7.0 sends
-- ============================================================================
CREATE OR REPLACE FUNCTION insert_appointment(
  -- Parameters in the EXACT order n8n sends them
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
  p_appt_valid BOOLEAN DEFAULT TRUE,  -- THE MISSING PARAMETER!
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
    'pending',  -- outcome_status always starts as pending
    COALESCE(p_created_source, 'ai_automated'),
    COALESCE(p_source_workflow, 'drive_ai_7'),
    NOW(),
    NOW(),
    NOW()
  )
  RETURNING id INTO v_result_id;

  -- Update the leads table to track appointment booking
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

  -- Return success
  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_result_id,
    'ghl_appointment_id', p_ghl_appointment_id,
    'action', 'inserted',
    'created_source', p_created_source,
    'source_workflow', p_source_workflow,
    'trace_id', p_trace_id,
    'appt_valid', p_appt_valid
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION insert_appointment(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, BOOLEAN, TEXT, TEXT, TEXT, TEXT
) TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- After running this SQL, the function should accept these EXACT parameters:
--
-- {
--   "p_ghl_appointment_id": "x4TmsLL7cKBWxlXc2Iy8",
--   "p_trace_id": "1245721f-51a4-4624-9e2d-dc469de12f13",
--   "p_calendar_id": "mkbB1KGgegeRxRqjgfjI",
--   "p_location_id": "RMMkdOgBaw5tjVTzSeQ9",
--   "p_dealership_name": "Camacho Mitsubishi",
--   "p_dealership_address": "123 Main St",
--   "p_dealership_hours": "9am-7pm",
--   "p_dealership_timezone": "America/Chicago",
--   "p_contact_id": "vh3G7RVybIi0cUaU3Kzu",
--   "p_lead_name": "Andrea Leffingwell",
--   "p_lead_first_name": "Andrea",
--   "p_lead_phone": "+15551234567",
--   "p_lead_email": "andrea@example.com",
--   "p_assigned_rep_id": "rep123",
--   "p_assigned_rep_name": "John Smith",
--   "p_title": "Andrea - Store Appointment",
--   "p_appointment_type": "Store Appointment",
--   "p_appointment_time": "2026-01-20T15:00:00Z",
--   "p_appointment_summary": "Customer wants to test drive",
--   "p_appt_valid": true,
--   "p_status": "booked",
--   "p_appointment_status": "confirmed",
--   "p_created_source": "ai_automated",
--   "p_source_workflow": "drive_ai_7"
-- }
--
-- Test with:
-- SELECT insert_appointment(
--   'TEST123',           -- p_ghl_appointment_id
--   'trace-123',         -- p_trace_id
--   'cal-123',           -- p_calendar_id
--   'RMMkdOgBaw5tjVTzSeQ9', -- p_location_id
--   'Test Dealer',       -- p_dealership_name
--   '123 Main St',       -- p_dealership_address
--   '9-5',               -- p_dealership_hours
--   'America/Chicago',   -- p_dealership_timezone
--   'contact-123',       -- p_contact_id
--   'Test User',         -- p_lead_name
--   'Test',              -- p_lead_first_name
--   '+15551234567',      -- p_lead_phone
--   'test@test.com',     -- p_lead_email
--   'rep-123',           -- p_assigned_rep_id
--   'John Rep',          -- p_assigned_rep_name
--   'Test Appointment',  -- p_title
--   'Store Appointment', -- p_appointment_type
--   NOW() + INTERVAL '1 day', -- p_appointment_time
--   'Test summary',      -- p_appointment_summary
--   true,                -- p_appt_valid
--   'booked',            -- p_status
--   'confirmed',         -- p_appointment_status
--   'ai_automated',      -- p_created_source
--   'drive_ai_7'         -- p_source_workflow
-- );
--
-- Then cleanup:
-- DELETE FROM appointments WHERE ghl_appointment_id = 'TEST123';
-- ============================================================================
