-- ============================================================================
-- DRIVE AI 7.0 - Upsert Appointment Function
-- ============================================================================
-- This function handles INSERT or UPDATE for appointments based on GHL ID
-- Maintains source priority: rep_instructed > ai_automated > user_booked
-- ============================================================================

-- Drop existing function if it exists (to replace it)
DROP FUNCTION IF EXISTS upsert_appointment_from_ghl(JSONB);

-- ============================================================================
-- MAIN UPSERT FUNCTION
-- ============================================================================
-- Called by: ghl-appointment-webhook edge function
-- Purpose: Insert new appointments OR update existing ones
-- Key: Uses ghl_appointment_id as the unique identifier
-- ============================================================================

CREATE OR REPLACE FUNCTION upsert_appointment_from_ghl(payload JSONB)
RETURNS JSONB AS $$
DECLARE
  v_ghl_appointment_id TEXT;
  v_location_id TEXT;
  v_contact_id TEXT;
  v_outcome_status TEXT;
  v_appointment_status TEXT;
  v_existing_record RECORD;
  v_result_id UUID;
  v_rows_updated INT := 0;
  v_is_insert BOOLEAN := FALSE;
  v_final_source TEXT;
BEGIN
  -- Extract key fields from payload
  v_ghl_appointment_id := payload->>'appointmentId';
  v_location_id := payload->>'locationId';
  v_contact_id := payload->>'contactId';
  v_outcome_status := LOWER(COALESCE(payload->>'status', payload->>'appointmentStatus', 'pending'));
  v_appointment_status := LOWER(COALESCE(payload->>'appointmentStatus', 'pending'));

  -- Normalize outcome status from GHL values
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

  -- Validate required fields
  IF v_ghl_appointment_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Missing appointmentId',
      'extracted_appt_id', v_ghl_appointment_id
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

    -- Determine if we should update outcome_status
    -- Only update if:
    -- 1. New status is more "final" (showed/no_show > confirmed > pending)
    -- 2. Or existing status is pending/confirmed

    UPDATE appointments
    SET
      outcome_status = CASE
        -- Always update if current is pending
        WHEN outcome_status = 'pending' THEN v_outcome_status
        -- Update from confirmed to showed/no_show/cancelled
        WHEN outcome_status = 'confirmed' AND v_outcome_status IN ('showed', 'no_show', 'cancelled') THEN v_outcome_status
        -- Update if explicitly setting confirmed
        WHEN v_outcome_status = 'confirmed' AND outcome_status = 'pending' THEN v_outcome_status
        -- Keep existing status otherwise
        ELSE outcome_status
      END,
      outcome_recorded_at = CASE
        WHEN v_outcome_status IN ('showed', 'no_show', 'cancelled')
          AND outcome_status NOT IN ('showed', 'no_show', 'cancelled')
        THEN NOW()
        ELSE outcome_recorded_at
      END,
      appointment_status = COALESCE(NULLIF(v_appointment_status, ''), appointment_status),
      -- Update contact info if provided and not already set
      lead_name = COALESCE(NULLIF(payload->>'contactName', ''), NULLIF(payload->>'leadName', ''), lead_name),
      lead_phone = COALESCE(NULLIF(payload->>'phone', ''), lead_phone),
      lead_email = COALESCE(NULLIF(payload->>'email', ''), lead_email),
      -- Update appointment time if provided
      appointment_time = COALESCE(
        (payload->>'startTime')::TIMESTAMPTZ,
        (payload->>'appointmentTime')::TIMESTAMPTZ,
        appointment_time
      ),
      title = COALESCE(NULLIF(payload->>'title', ''), title),
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

    -- For new appointments from GHL webhook, source is 'user_booked'
    -- unless explicitly specified otherwise
    v_final_source := COALESCE(NULLIF(payload->>'createdSource', ''), 'user_booked');

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
      payload->>'timezone',
      COALESCE(payload->>'contactName', payload->>'leadName'),
      payload->>'firstName',
      payload->>'phone',
      payload->>'email',
      payload->>'assignedUserId',
      payload->>'assignedUserName',
      COALESCE(payload->>'title', 'Appointment'),
      COALESCE(payload->>'appointmentType', 'Store Appointment'),
      COALESCE(
        (payload->>'startTime')::TIMESTAMPTZ,
        (payload->>'appointmentTime')::TIMESTAMPTZ,
        NOW()
      ),
      v_appointment_status,
      v_outcome_status,
      COALESCE(payload->>'status', 'booked'),
      v_final_source,
      'ghl_webhook',
      payload->>'calendarId',
      NOW(),
      NOW(),
      COALESCE((payload->>'dateAdded')::TIMESTAMPTZ, NOW())
    )
    RETURNING id INTO v_result_id;

    v_rows_updated := 1;
    v_is_insert := TRUE;

    -- Also update the leads table to track appointment
    UPDATE leads
    SET
      appointment_booked = TRUE,
      appointment_count = COALESCE(appointment_count, 0) + 1,
      first_appointment_at = COALESCE(first_appointment_at, NOW()),
      updated_at = NOW()
    WHERE contact_id = v_contact_id
      AND location_id = v_location_id;

  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'success', v_result_id IS NOT NULL,
    'appointment_id', v_result_id,
    'outcome_status', v_outcome_status,
    'rows_updated', v_rows_updated,
    'is_insert', v_is_insert,
    'created_source', v_final_source,
    'extracted_appt_id', v_ghl_appointment_id,
    'extracted_location_id', v_location_id,
    'extracted_contact_id', v_contact_id,
    'raw_status', payload->>'status'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'error_detail', SQLSTATE,
    'extracted_appt_id', v_ghl_appointment_id,
    'extracted_location_id', v_location_id,
    'extracted_contact_id', v_contact_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION upsert_appointment_from_ghl(JSONB) TO anon, authenticated, service_role;


-- ============================================================================
-- UPDATE THE EDGE FUNCTION
-- ============================================================================
-- The edge function at: /functions/v1/ghl-appointment-webhook
-- needs to call this new function instead of just doing an UPDATE
--
-- Change from:
--   UPDATE appointments SET outcome_status = ... WHERE ghl_appointment_id = ...
--
-- Change to:
--   SELECT upsert_appointment_from_ghl(payload)
-- ============================================================================

-- ============================================================================
-- EDGE FUNCTION CODE (for reference - deploy via Supabase CLI)
-- ============================================================================
-- Save this as: supabase/functions/ghl-appointment-webhook/index.ts
-- ============================================================================
/*
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const payload = await req.json()

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Call the upsert function
    const { data, error } = await supabaseClient.rpc('upsert_appointment_from_ghl', {
      payload: payload
    })

    if (error) {
      console.error('RPC Error:', error)
      return new Response(
        JSON.stringify({ success: false, error: error.message }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    return new Response(
      JSON.stringify(data),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (err) {
    console.error('Error:', err)
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
*/


-- ============================================================================
-- VERIFICATION QUERY
-- ============================================================================
-- Run this after deploying to verify the function works:
--
-- SELECT upsert_appointment_from_ghl('{
--   "appointmentId": "TEST123",
--   "locationId": "RMMkdOgBaw5tjVTzSeQ9",
--   "contactId": "TEST_CONTACT",
--   "status": "confirmed",
--   "contactName": "Test User",
--   "phone": "+15551234567"
-- }'::jsonb);
--
-- Then check:
-- SELECT * FROM appointments WHERE ghl_appointment_id = 'TEST123';
-- DELETE FROM appointments WHERE ghl_appointment_id = 'TEST123'; -- cleanup
-- ============================================================================


-- ============================================================================
-- SOURCE PRIORITY DOCUMENTATION
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
--    - Created by: insert_appointment RPC (from Drive AI 7.0)
--
-- 3. 'user_booked' - Appointment booked directly in GHL
--    - No reactivation_id
--    - Can be "upgraded" to rep_instructed if rep closes the loop
--    - Created by: upsert_appointment_from_ghl (this function)
--
-- The upsert function will:
-- - INSERT new appointments as 'user_booked' (or whatever source specified)
-- - UPDATE outcome_status regardless of source
-- - NEVER overwrite created_source once set (preserves original source)
-- ============================================================================
