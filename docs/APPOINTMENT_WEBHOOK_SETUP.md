# Appointment Webhook Setup (Unified Endpoint)

## Overview

This document describes how to set up the GHL appointment webhook to capture ALL appointments and status updates through a single endpoint.

## The Problem

Currently, appointments are only captured when created by:
- **Drive AI 7.0** → `created_source = 'ai_automated'`
- **Reactivate Drive** → `created_source = 'rep_instructed'`

Appointments created manually in GHL's calendar are NOT captured, leading to significant data gaps.

## The Solution

Use the existing `ghl-appointment-webhook` endpoint to handle BOTH:
1. **New bookings** (status = "confirmed") → Insert as `rep_manual` if not from n8n
2. **Status updates** (showed, no_show, cancelled) → Update outcome

### Key Logic

```
IF status = "confirmed" AND appointment doesn't exist:
    → INSERT with created_source = 'rep_manual' (passive UPSERT)
    → If n8n already inserted, do nothing

IF appointment exists:
    → UPDATE outcome_status (showed, no_show, cancelled)

IF appointment doesn't exist AND status != "confirmed":
    → Skip (outcome for appointment we don't have)
```

---

## Step 1: Run the SQL Migration

Run the migration in Supabase SQL Editor:

**File:** `migrations/option2_appointment_upsert.sql`

This migration:
1. Adds unique constraint on `ghl_appointment_id`
2. Updates `insert_appointment()` to use ON CONFLICT DO UPDATE (n8n wins)
3. Creates `upsert_appointment_from_webhook()` with passive UPSERT logic
4. Updates views to include `rep_manual` in human counts

---

## Step 2: Deploy the Edge Function

```bash
supabase functions deploy ghl-appointment-webhook
```

**URL:**
```
https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook
```

---

## Step 3: Set Up GHL Webhooks

You need TWO webhook triggers in GHL, both pointing to the same endpoint:

### Webhook 1: Appointment Created

| Field | Value |
|-------|-------|
| **Name** | Appointment Created |
| **Trigger** | Appointment Created |
| **URL** | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook` |
| **Method** | POST |

### Webhook 2: Appointment Status Changed

| Field | Value |
|-------|-------|
| **Name** | Appointment Status Changed |
| **Trigger** | Appointment Status Changed |
| **URL** | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook` |
| **Method** | POST |

### Required Headers (for both):

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdhbXdpbWFtY3ZnYWtjZXRkeXBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNDM0NzAsImV4cCI6MjA4MjYxOTQ3MH0.CuhNBluIOX6bMukLuvnmtd6gCq1k8fTVAL-xRDcUbis
Content-Type: application/json
```

---

## How Deduplication Works

### The Race Condition Problem

When Drive AI 7.0 or Reactivate Drive creates an appointment:
1. n8n workflow calls `insert_appointment()` → inserts to Supabase
2. GHL fires "Appointment Created" webhook → also tries to insert

**Who fires first is unpredictable!**

### The Solution: Authoritative vs Passive

| Source | Function | Conflict Strategy | Authority |
|--------|----------|-------------------|-----------|
| n8n (Drive AI / Reactivate) | `insert_appointment()` | ON CONFLICT DO UPDATE | **Authoritative** (always wins) |
| GHL Webhook | `upsert_appointment_from_webhook()` | Check exists first, skip if yes | **Passive** (defers to n8n) |

### Scenario Walkthrough

**Scenario A: n8n fires first (expected)**
```
1. Drive AI 7.0 → insert_appointment() → created_source = 'ai_automated'
2. GHL webhook fires → checks if exists → YES → skips insert
✅ Result: ai_automated (correct)
```

**Scenario B: GHL webhook fires first (edge case)**
```
1. GHL webhook fires → checks if exists → NO → inserts as 'rep_manual'
2. Drive AI 7.0 → insert_appointment() → ON CONFLICT DO UPDATE
3. Overwrites created_source = 'ai_automated'
✅ Result: ai_automated (correct - n8n overrides)
```

**Scenario C: Manual creation (no n8n involved)**
```
1. Rep books directly in GHL calendar
2. GHL webhook fires → checks if exists → NO → inserts as 'rep_manual'
3. No n8n workflow runs (this was truly manual)
✅ Result: rep_manual (correct)
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     APPOINTMENT EVENTS                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐   ┌──────────────┐   ┌─────────────────┐           │
│  │  Drive AI   │   │  Reactivate  │   │   Rep Manual    │           │
│  │    7.0      │   │    Drive     │   │  (GHL Calendar) │           │
│  └──────┬──────┘   └──────┬───────┘   └────────┬────────┘           │
│         │                 │                     │                     │
│         │ (n8n)           │ (n8n)               │ (no n8n)           │
│         ▼                 ▼                     ▼                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │               GHL Creates/Updates Appointment                │   │
│  │                                                              │   │
│  │  status = "confirmed" → New booking                          │   │
│  │  status = "showed/no_show/cancelled" → Outcome update        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                 │                     │                     │
│         │                 │                     │                     │
│    ┌────┴────┐       ┌────┴────┐          ┌────┴────┐               │
│    │   n8n   │       │   n8n   │          │   GHL   │               │
│    │ insert  │       │ insert  │          │ webhook │               │
│    │ (AUTH)  │       │ (AUTH)  │          │(PASSIVE)│               │
│    └────┬────┘       └────┬────┘          └────┬────┘               │
│         │                 │                     │                     │
│         ▼                 ▼                     ▼                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                  ghl-appointment-webhook                     │   │
│  │                                                              │   │
│  │  IF status = "confirmed" AND not exists:                     │   │
│  │      → INSERT as 'rep_manual'                                │   │
│  │      → But n8n will override if it runs                      │   │
│  │                                                              │   │
│  │  IF exists:                                                  │   │
│  │      → UPDATE outcome_status                                 │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                 │                     │                     │
│         ▼                 ▼                     ▼                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                   Supabase: appointments                     │   │
│  │                                                              │   │
│  │  created_source:                                             │   │
│  │    'ai_automated'   → AI booked (Drive AI 7.0)              │   │
│  │    'rep_instructed' → Rep instructed (Reactivate Drive)     │   │
│  │    'rep_manual'     → Rep booked directly in GHL            │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Status Mapping

### New Booking
| GHL Status | Action |
|------------|--------|
| `confirmed` | Insert new appointment (if not exists) |

### Outcome Updates
| GHL Status | Maps To | Action |
|------------|---------|--------|
| `showed`, `completed` | `showed` | Update outcome |
| `no_show`, `no-show`, `noshow` | `no_show` | Update outcome |
| `cancelled`, `canceled` | `cancelled` | Update outcome |
| `rescheduled` | `cancelled` | Update outcome |

---

## Human-AI Ratio Calculation

```sql
-- AI appointments
ai_booked = COUNT(*) WHERE created_source = 'ai_automated'

-- Human appointments (BOTH types)
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

## Verification Queries

After setup, run these to verify:

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

-- Verify outcome updates are working
SELECT
    outcome_status,
    COUNT(*) as count
FROM appointments
WHERE appointment_time < NOW()
GROUP BY outcome_status;

-- Compare totals with GHL by dealership
SELECT
    d.dealership_name,
    COUNT(a.id) as supabase_total,
    COUNT(a.id) FILTER (WHERE a.created_source = 'ai_automated') as ai,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_instructed') as rep_instructed,
    COUNT(a.id) FILTER (WHERE a.created_source = 'rep_manual') as rep_manual
FROM v_dealerships d
LEFT JOIN appointments a ON d.location_id = a.location_id
GROUP BY d.dealership_name
ORDER BY supabase_total DESC;
```

---

## Troubleshooting

### Webhook not firing
- Check GHL webhook logs in Settings → Webhooks
- Verify the webhook is enabled for all sub-accounts
- Ensure both "Appointment Created" AND "Appointment Status Changed" triggers are set up

### Appointments still missing
- Check Supabase Edge Function logs for errors
- Verify the authorization header is correct
- Check if `ghl_appointment_id` is being passed in the payload

### Duplicate appointments
- This shouldn't happen with the UPSERT logic
- Verify unique constraint exists: `appointments_ghl_appointment_id_key`
- Check Edge Function logs for "skipped_existing" messages

### Wrong created_source
- If an AI appointment shows as `rep_manual`, check if n8n workflow is running
- Verify n8n is using `insert_appointment()` with ON CONFLICT DO UPDATE

---

## Files

| File | Purpose |
|------|---------|
| `migrations/option2_appointment_upsert.sql` | SQL migration with RPC functions and views |
| `supabase/functions/ghl-appointment-webhook/index.ts` | Unified edge function |
| `docs/APPOINTMENT_WEBHOOK_SETUP.md` | This documentation |
