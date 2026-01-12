# Appointment Created Webhook Setup

## Overview

This document describes how to set up the GHL "Appointment Created" webhook to capture all appointments, including those created manually by reps in GHL.

## The Problem

Currently, appointments are only captured when created by:
- **Drive AI 7.0** → `created_source = 'ai_automated'`
- **Reactivate Drive** → `created_source = 'rep_instructed'`

Appointments created manually in GHL's calendar are NOT captured, leading to significant data gaps.

## The Solution

Add a GHL webhook that fires when ANY appointment is created. This webhook uses passive UPSERT logic:
- If n8n already inserted the appointment → **does nothing** (respects authoritative source)
- If appointment is new (manual creation) → **inserts with `created_source = 'rep_manual'`**

---

## Step 1: Run the SQL Migration

Run the migration in Supabase SQL Editor:

**File:** `migrations/option2_appointment_upsert.sql`

This migration:
1. Adds unique constraint on `ghl_appointment_id`
2. Updates `insert_appointment()` to use ON CONFLICT DO UPDATE (n8n wins)
3. Creates `upsert_appointment_from_webhook()` with ON CONFLICT DO NOTHING (webhook defers)
4. Updates views to include `rep_manual` in human counts

---

## Step 2: Deploy the Edge Function

```bash
supabase functions deploy ghl-appointment-created
```

**URL after deployment:**
```
https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-created
```

---

## Step 3: Set Up GHL Webhook

### In GHL Agency Settings:

1. Go to **Settings** → **Webhooks**
2. Click **Add Webhook**
3. Configure:

| Field | Value |
|-------|-------|
| **Name** | Appointment Created |
| **Trigger** | Appointment Created |
| **URL** | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-created` |
| **Method** | POST |

### Required Headers:

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdhbXdpbWFtY3ZnYWtjZXRkeXBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNDM0NzAsImV4cCI6MjA4MjYxOTQ3MH0.CuhNBluIOX6bMukLuvnmtd6gCq1k8fTVAL-xRDcUbis
Content-Type: application/json
```

---

## Data Flow After Setup

```
┌─────────────────────────────────────────────────────────────────┐
│                    APPOINTMENT CREATION                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐   │
│  │  Drive AI   │     │  Reactivate  │     │  Rep Manual     │   │
│  │   7.0       │     │    Drive     │     │  (GHL Calendar) │   │
│  └──────┬──────┘     └──────┬───────┘     └────────┬────────┘   │
│         │                   │                      │             │
│         ▼                   ▼                      ▼             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    GHL Creates Appointment               │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                   │                      │             │
│         │                   │                      │             │
│         ▼                   ▼                      ▼             │
│  ┌──────────────┐    ┌──────────────┐     ┌──────────────────┐  │
│  │   n8n        │    │    n8n       │     │  GHL Webhook     │  │
│  │ insert_appt  │    │ insert_appt  │     │ (fires for all)  │  │
│  │ AUTHORITATIVE│    │ AUTHORITATIVE│     │                  │  │
│  └──────┬───────┘    └──────┬───────┘     └────────┬─────────┘  │
│         │                   │                      │             │
│         ▼                   ▼                      ▼             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Supabase appointments table            │   │
│  │                                                          │   │
│  │  ON CONFLICT:                                            │   │
│  │  - n8n uses DO UPDATE (wins, overrides)                  │   │
│  │  - Webhook uses DO NOTHING (defers if exists)            │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  RESULT:                                                         │
│  ┌────────────────┬───────────────────────────────────────────┐ │
│  │ created_source │ Description                               │ │
│  ├────────────────┼───────────────────────────────────────────┤ │
│  │ ai_automated   │ AI booked via Drive AI 7.0               │ │
│  │ rep_instructed │ Rep instructed via Reactivate Drive      │ │
│  │ rep_manual     │ Rep booked directly in GHL calendar      │ │
│  └────────────────┴───────────────────────────────────────────┘ │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Race Condition Handling

**Scenario A: n8n fires first (expected)**
```
1. n8n inserts with created_source = 'ai_automated'
2. GHL webhook fires, sees existing record
3. Webhook does nothing (ON CONFLICT DO NOTHING)
✅ Correct: ai_automated
```

**Scenario B: GHL webhook fires first (edge case)**
```
1. GHL webhook fires, inserts with created_source = 'rep_manual'
2. n8n fires, sees existing record
3. n8n UPDATES with created_source = 'ai_automated' (ON CONFLICT DO UPDATE)
✅ Correct: ai_automated (n8n overrides)
```

**Scenario C: Manual creation (no n8n)**
```
1. Rep books appointment directly in GHL calendar
2. GHL webhook fires, no existing record
3. Webhook inserts with created_source = 'rep_manual'
✅ Correct: rep_manual
```

---

## Human-AI Ratio Calculation

After this change, the ratio is calculated as:

```sql
-- AI appointments
ai_booked = COUNT(*) WHERE created_source = 'ai_automated'

-- Human appointments (both types)
human_booked = COUNT(*) WHERE created_source IN ('rep_instructed', 'rep_manual')

-- Ratio
ai_human_ratio = ai_booked / human_booked
```

### Balance Status

| Status | Ratio | Meaning |
|--------|-------|---------|
| `BALANCED` | 0.8 - 1.2 | AI and humans booking equally |
| `AI_UNDERUTILIZED` | < 0.5 | Humans booking more, AI could help |
| `STAFF_UNDERPERFORMING` | > 2.0 | AI doing most work, staff not engaging |

---

## Verification

After setup, run this query to verify appointments are being captured:

```sql
-- Check created_source distribution
SELECT
    created_source,
    COUNT(*) as count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 1) as pct
FROM appointments
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY created_source
ORDER BY count DESC;

-- Compare with GHL
SELECT
    d.dealership_name,
    COUNT(a.id) as supabase_total,
    COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated') as ai,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_instructed') as rep_instructed,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_manual') as rep_manual
FROM v_dealerships d
LEFT JOIN appointments a ON d.location_id = a.location_id
    AND a.created_at > NOW() - INTERVAL '7 days'
GROUP BY d.dealership_name
ORDER BY supabase_total DESC;
```

---

## Troubleshooting

### Webhook not firing
- Check GHL webhook logs in Settings → Webhooks
- Verify the webhook is enabled for all sub-accounts

### Appointments still missing
- Check Supabase Edge Function logs for errors
- Verify the authorization header is correct
- Check if `ghl_appointment_id` is being passed correctly

### Duplicate appointments
- This shouldn't happen with the UPSERT logic
- Check the unique constraint exists: `appointments_ghl_appointment_id_key`

---

## Files Created

| File | Purpose |
|------|---------|
| `migrations/option2_appointment_upsert.sql` | SQL migration with RPC functions and views |
| `supabase/functions/ghl-appointment-created/index.ts` | Edge function for webhook |
| `docs/APPOINTMENT_WEBHOOK_SETUP.md` | This documentation |
