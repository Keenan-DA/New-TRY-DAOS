// Edge Function: ghl-appointment-webhook
// Purpose: Handle ALL GHL appointment events (new bookings + status updates)
//
// Logic:
// 1. If status = "confirmed" AND appointment doesn't exist → INSERT as rep_manual
// 2. If appointment exists → UPDATE outcome status
//
// Deduplication:
// - Uses ghl_appointment_id as unique key
// - n8n workflows (Drive AI 7.0, Reactivate Drive) use ON CONFLICT DO UPDATE (authoritative)
// - This webhook uses ON CONFLICT DO NOTHING (passive) for new appointments
// - Result: n8n always wins, no duplicates

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface AppointmentWebhookPayload {
  // Appointment identifiers
  id?: string
  appointmentId?: string

  // Location & Contact
  locationId?: string
  location_id?: string
  contactId?: string
  contact_id?: string
  calendarId?: string

  // Status - KEY FIELD
  // "confirmed" = new booking
  // "showed", "no_show", "cancelled", "rescheduled" = outcome update
  status?: string
  appointmentStatus?: string

  // Assignment
  assignedUserId?: string
  assignedUserName?: string

  // Appointment details
  title?: string
  appointmentType?: string
  startTime?: string
  start_time?: string

  // Who created/modified
  createdBy?: string
  userId?: string
  createdByUser?: {
    id?: string
    name?: string
    firstName?: string
    lastName?: string
  }

  // Source info
  source?: string
  workflowId?: string

  // Contact info (sometimes included)
  contact?: {
    id?: string
    name?: string
    firstName?: string
    lastName?: string
    phone?: string
    email?: string
  }
}

// Map GHL status to our outcome_status
function mapStatusToOutcome(status: string): string | null {
  const statusMap: Record<string, string> = {
    'showed': 'showed',
    'completed': 'showed',
    'no_show': 'no_show',
    'no-show': 'no_show',
    'noshow': 'no_show',
    'cancelled': 'cancelled',
    'canceled': 'cancelled',
    'rescheduled': 'cancelled', // Treat reschedule as cancelled for this appointment
  }
  return statusMap[status?.toLowerCase()] || null
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Parse webhook payload
    const payload: AppointmentWebhookPayload = await req.json()

    console.log('Received appointment webhook:', JSON.stringify(payload, null, 2))

    // Extract appointment ID (GHL sends it in different fields)
    const ghlAppointmentId = payload.id || payload.appointmentId
    if (!ghlAppointmentId) {
      return new Response(
        JSON.stringify({ error: 'Missing appointment ID', payload }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract status
    const status = (payload.status || payload.appointmentStatus || '').toLowerCase()
    console.log(`Processing appointment ${ghlAppointmentId} with status: ${status}`)

    // Check if appointment already exists
    const { data: existingAppt, error: lookupError } = await supabase
      .from('appointments')
      .select('id, created_source, outcome_status')
      .eq('ghl_appointment_id', ghlAppointmentId)
      .maybeSingle()

    if (lookupError) {
      console.error('Lookup error:', lookupError)
      return new Response(
        JSON.stringify({ error: 'Database lookup failed', details: lookupError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // DECISION POINT: New booking vs Status update
    if (!existingAppt && status === 'confirmed') {
      // ============================================
      // NEW BOOKING - Insert as rep_manual
      // ============================================
      console.log('New booking detected - inserting as rep_manual')

      const locationId = payload.locationId || payload.location_id
      const contactId = payload.contactId || payload.contact_id || payload.contact?.id

      if (!locationId || !contactId) {
        return new Response(
          JSON.stringify({
            error: 'Missing locationId or contactId for new booking',
            locationId,
            contactId
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Parse appointment time
      let appointmentTime: string | null = null
      const rawTime = payload.startTime || payload.start_time
      if (rawTime) {
        try {
          appointmentTime = new Date(rawTime).toISOString()
        } catch {
          console.warn('Could not parse startTime:', rawTime)
        }
      }

      // Get assigned rep info
      const assignedRepId = payload.assignedUserId || null
      const assignedRepName = payload.assignedUserName ||
        (payload.createdByUser?.firstName && payload.createdByUser?.lastName
          ? `${payload.createdByUser.firstName} ${payload.createdByUser.lastName}`
          : payload.createdByUser?.name) || null

      // Call the passive UPSERT RPC
      const { data: insertResult, error: insertError } = await supabase.rpc(
        'upsert_appointment_from_webhook',
        {
          p_ghl_appointment_id: ghlAppointmentId,
          p_location_id: locationId,
          p_contact_id: contactId,
          p_calendar_id: payload.calendarId || null,
          p_assigned_rep_id: assignedRepId,
          p_assigned_rep_name: assignedRepName,
          p_title: payload.title || null,
          p_appointment_type: payload.appointmentType || null,
          p_appointment_time: appointmentTime,
          p_status: status,
          p_appointment_status: 'confirmed',
          p_created_by_user_id: payload.createdBy || payload.userId || null,
          p_created_by_user_name: assignedRepName,
          p_booking_source: payload.source || 'ghl_calendar',
          p_raw_data: payload
        }
      )

      if (insertError) {
        console.error('Insert RPC error:', insertError)
        return new Response(
          JSON.stringify({ error: 'Failed to insert appointment', details: insertError.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const result = insertResult?.[0] || insertResult
      console.log('Insert result:', result)

      return new Response(
        JSON.stringify({
          success: true,
          action: result?.action_taken || 'inserted',
          appointment_id: result?.appointment_id,
          created_source: result?.created_source,
          message: result?.action_taken === 'skipped_existing'
            ? 'Appointment already exists (from n8n workflow) - no action taken'
            : 'New manual appointment created with created_source=rep_manual'
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else if (existingAppt) {
      // ============================================
      // EXISTING APPOINTMENT - Update outcome status
      // ============================================
      const outcomeStatus = mapStatusToOutcome(status)

      if (!outcomeStatus) {
        // Status is "confirmed" on existing appt - likely a duplicate webhook, ignore
        console.log(`Ignoring status "${status}" for existing appointment`)
        return new Response(
          JSON.stringify({
            success: true,
            action: 'ignored',
            message: `Status "${status}" does not map to an outcome - no update needed`,
            existing_source: existingAppt.created_source
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      console.log(`Updating appointment ${ghlAppointmentId} outcome to: ${outcomeStatus}`)

      // Update the outcome status
      const { error: updateError } = await supabase
        .from('appointments')
        .update({
          outcome_status: outcomeStatus,
          outcome_recorded_at: new Date().toISOString(),
          outcome_recorded_by: 'ghl_webhook',
          updated_at: new Date().toISOString()
        })
        .eq('ghl_appointment_id', ghlAppointmentId)

      if (updateError) {
        console.error('Update error:', updateError)
        return new Response(
          JSON.stringify({ error: 'Failed to update outcome', details: updateError.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      return new Response(
        JSON.stringify({
          success: true,
          action: 'updated_outcome',
          appointment_id: existingAppt.id,
          previous_outcome: existingAppt.outcome_status,
          new_outcome: outcomeStatus,
          created_source: existingAppt.created_source
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else {
      // ============================================
      // NO EXISTING APPOINTMENT + NOT "confirmed"
      // ============================================
      // This is an outcome update for an appointment we don't have
      // Could be: appointment created before we started tracking, or data issue
      console.warn(`Received status "${status}" for unknown appointment ${ghlAppointmentId}`)

      return new Response(
        JSON.stringify({
          success: false,
          action: 'skipped',
          message: `Appointment ${ghlAppointmentId} not found and status "${status}" is not a new booking`,
          suggestion: 'This appointment may have been created before webhook integration'
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

  } catch (err) {
    console.error('Webhook error:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
