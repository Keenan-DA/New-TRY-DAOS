// Edge Function: ghl-appointment-created
// Purpose: Handle GHL "Appointment Created" webhook
// Uses passive UPSERT - defers to n8n if appointment already exists

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface AppointmentWebhookPayload {
  // Standard GHL appointment fields
  id?: string
  appointmentId?: string
  calendarId?: string
  locationId?: string
  contactId?: string
  assignedUserId?: string
  assignedUserName?: string
  title?: string
  appointmentType?: string
  startTime?: string
  status?: string
  appointmentStatus?: string
  // Who created it
  createdBy?: string
  createdByUser?: {
    id?: string
    name?: string
    firstName?: string
    lastName?: string
  }
  userId?: string
  userName?: string
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

    console.log('Received appointment created webhook:', JSON.stringify(payload, null, 2))

    // Extract appointment ID (GHL sends it in different fields)
    const ghlAppointmentId = payload.id || payload.appointmentId
    if (!ghlAppointmentId) {
      return new Response(
        JSON.stringify({ error: 'Missing appointment ID' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract location and contact IDs
    const locationId = payload.locationId
    const contactId = payload.contactId || payload.contact?.id
    if (!locationId || !contactId) {
      return new Response(
        JSON.stringify({ error: 'Missing locationId or contactId' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract assigned rep info
    const assignedRepId = payload.assignedUserId
    const assignedRepName = payload.assignedUserName ||
      (payload.createdByUser?.firstName && payload.createdByUser?.lastName
        ? `${payload.createdByUser.firstName} ${payload.createdByUser.lastName}`
        : payload.createdByUser?.name)

    // Extract who created it (for attribution tracking)
    const createdByUserId = payload.createdBy || payload.userId || payload.createdByUser?.id
    const createdByUserName = payload.userName || payload.createdByUser?.name ||
      (payload.createdByUser?.firstName && payload.createdByUser?.lastName
        ? `${payload.createdByUser.firstName} ${payload.createdByUser.lastName}`
        : null)

    // Parse appointment time
    let appointmentTime: string | null = null
    if (payload.startTime) {
      try {
        appointmentTime = new Date(payload.startTime).toISOString()
      } catch {
        console.warn('Could not parse startTime:', payload.startTime)
      }
    }

    // Call the RPC function
    const { data, error } = await supabase.rpc('upsert_appointment_from_webhook', {
      p_ghl_appointment_id: ghlAppointmentId,
      p_location_id: locationId,
      p_contact_id: contactId,
      p_calendar_id: payload.calendarId || null,
      p_assigned_rep_id: assignedRepId || null,
      p_assigned_rep_name: assignedRepName || null,
      p_title: payload.title || null,
      p_appointment_type: payload.appointmentType || null,
      p_appointment_time: appointmentTime,
      p_status: payload.status || null,
      p_appointment_status: payload.appointmentStatus || 'confirmed',
      p_created_by_user_id: createdByUserId || null,
      p_created_by_user_name: createdByUserName || null,
      p_booking_source: payload.source || 'ghl_calendar',
      p_raw_data: payload
    })

    if (error) {
      console.error('RPC error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the result
    const result = data?.[0] || data
    console.log('RPC result:', result)

    return new Response(
      JSON.stringify({
        success: true,
        appointment_id: result?.appointment_id,
        action: result?.action_taken,
        created_source: result?.created_source,
        message: result?.action_taken === 'skipped_existing'
          ? 'Appointment already exists (from n8n workflow)'
          : 'New manual appointment created'
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    console.error('Webhook error:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
