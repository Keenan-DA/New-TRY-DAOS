# DA-OS Developer Guide

## Quick Start (5 minutes)

### Prerequisites
- Access to Supabase project: `gamwimamcvgakcetdypm`
- Access to GHL agency account
- Supabase CLI installed (`npm install -g supabase`)

### First Steps
1. Clone the repo
2. Read this guide
3. Review [DATA_DICTIONARY.md](DATA_DICTIONARY.md) for data structure
4. Review [ARCHITECTURE.md](ARCHITECTURE.md) for system design

---

## Project Overview

**DA-OS** (Dealer AI Operating System) tracks AI-assisted dealership operations:
- Lead intake and response times
- AI-generated tasks and completion rates
- Appointment booking and show rates
- Rep performance and adoption metrics

### Key Integrations

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│     GHL      │────►│     n8n      │────►│   Supabase   │
│  (CRM/Data)  │     │  (Workflows) │     │  (Database)  │
└──────────────┘     └──────────────┘     └──────────────┘
       │                                         │
       │         ┌──────────────┐               │
       └────────►│   Webhooks   │◄──────────────┘
                 │(Edge Functions)│
                 └──────────────┘
```

---

## Repository Structure

```
DA-OS/
├── README.md                      # Project overview
├── .gitignore                     # Ignored files
│
├── docs/                          # Documentation
│   ├── DEVELOPER_GUIDE.md         # THIS FILE - Start here
│   ├── ARCHITECTURE.md            # Data flow & system design
│   ├── SCHEMA.md                  # Complete database schema
│   ├── DATA_DICTIONARY.md         # Raw vs calculated data reference
│   ├── DASHBOARD_BLUEPRINT.md     # CS Dashboard specifications
│   ├── WEBHOOKS.md                # Webhook setup guide
│   └── diagrams/
│       └── data-flow.html         # Visual architecture diagram
│
├── supabase/
│   ├── migrations/                # SQL migrations (run in order)
│   │   ├── 002_appointment_upsert.sql
│   │   └── 003_critical_fixes.sql
│   └── functions/                 # Edge functions
│       └── ghl-appointment-webhook/
│           └── index.ts
│
└── data/                          # Local data (gitignored)
```

---

## Key Concepts

### 1. Data Sources

| Source | What It Sends | Destination |
|--------|---------------|-------------|
| **GHL Webhooks** | Lead created, messages, appointments | Edge Functions → Supabase |
| **n8n: Drive AI 7.0** | AI decisions, tasks, appointments | Supabase RPC |
| **n8n: Reactivate Drive** | Rep instructions, task completions | Supabase RPC |
| **n8n: Lead Tracker** | New lead records | Supabase RPC |

### 2. Appointment Attribution

| `created_source` | Meaning | Counts As |
|------------------|---------|-----------|
| `ai_automated` | AI booked via Drive AI 7.0 | AI |
| `rep_instructed` | Rep used Reactivate Drive form | Human |
| `rep_manual` | Rep booked directly in GHL calendar | Human |

### 3. Key Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `leads` | All contacts | `contact_id`, `location_id`, `lead_type` |
| `tasks` | AI-created follow-ups | `task_id`, `completed`, `due_date` |
| `appointments` | All bookings | `created_source`, `outcome_status` |
| `reactivations` | Rep instructions | `action`, `instruction` |
| `ai_decisions` | AI decision log | `action`, `confidence` |

### 4. Key Views

| View | Purpose | Key Metrics |
|------|---------|-------------|
| `v_appointment_stats` | Appointment metrics | `show_rate`, `ai_booked`, `human_booked` |
| `v_loop_closure_stats` | Task completion | `closed_loop_pct` |
| `v_health_score` | Adoption score | `adoption_score` (0-100) |
| `v_ai_human_ratio` | Booking attribution | `ai_human_ratio`, `balance_status` |

---

## Common Tasks

### Adding a New Migration

1. Create file: `supabase/migrations/00X_description.sql`
2. Follow naming convention: `00X_short_description.sql`
3. Include rollback comments if possible
4. Test in Supabase SQL Editor first
5. Commit and document changes

### Modifying a View

```sql
-- Views with column changes must be dropped first
DROP VIEW IF EXISTS v_my_view CASCADE;

CREATE OR REPLACE VIEW v_my_view AS
SELECT ...;

COMMENT ON VIEW v_my_view IS 'Description of what this view does';
```

### Adding a New RPC Function

```sql
CREATE OR REPLACE FUNCTION my_function(
    p_param1 TEXT,
    p_param2 INTEGER DEFAULT NULL
)
RETURNS UUID  -- or TABLE(...) for multiple columns
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Logic here
END;
$$;

COMMENT ON FUNCTION my_function IS 'What this function does';
```

### Deploying Edge Functions

```bash
# Deploy a single function
supabase functions deploy ghl-appointment-webhook

# Deploy all functions
supabase functions deploy
```

### Testing Webhooks Locally

```bash
# Start local Supabase
supabase start

# Serve functions locally
supabase functions serve ghl-appointment-webhook

# Test with curl
curl -X POST http://localhost:54321/functions/v1/ghl-appointment-webhook \
  -H "Content-Type: application/json" \
  -d '{"id": "test123", "status": "confirmed", "locationId": "xxx", "contactId": "yyy"}'
```

---

## Data Flow Details

### Lead Creation Flow

```
1. GHL: Contact Created
   ↓
2. n8n: Lead Tracker workflow
   ↓
3. Supabase: insert_lead() RPC
   ↓
4. Trigger: trg_leads_normalize_source
   - Looks up lead_source in dictionary
   - Sets lead_source_normalized
   ↓
5. Table: leads (new row)
```

### Appointment Creation Flow (AI)

```
1. GHL: Message received
   ↓
2. n8n: Drive AI 7.0 workflow
   ↓
3. AI: Analyzes conversation, decides "appointment"
   ↓
4. GHL API: Create appointment
   ↓
5. Supabase: insert_appointment(created_source='ai_automated')
   - Uses ON CONFLICT DO UPDATE (authoritative)
   ↓
6. GHL Webhook: Appointment Created (fires simultaneously)
   ↓
7. Edge Function: ghl-appointment-webhook
   ↓
8. Supabase: upsert_appointment_from_webhook()
   - Checks if exists → YES → skips (n8n already inserted)
   ↓
9. Result: Appointment with created_source='ai_automated'
```

### Appointment Creation Flow (Manual)

```
1. Rep: Books appointment in GHL calendar
   ↓
2. GHL Webhook: Appointment Created
   ↓
3. Edge Function: ghl-appointment-webhook
   ↓
4. Supabase: upsert_appointment_from_webhook()
   - Checks if exists → NO → inserts
   ↓
5. Result: Appointment with created_source='rep_manual'
```

### Speed to Lead Calculation

```
1. Lead created with lead_date
   ↓
2. First outbound sent (GHL webhook)
   ↓
3. Supabase: update_first_outbound()
   - Sets first_outbound_at
   ↓
4. Trigger: trg_leads_calculate_speed
   - IF lead_type = 'new_inbound'
   - AND source NOT IN ('Walk-In', 'Phone-Up')
   - THEN speed_to_lead_seconds = first_outbound_at - lead_date
```

---

## Troubleshooting

### Appointments Not Showing Up

1. Check Edge Function logs in Supabase dashboard
2. Verify GHL webhook is configured with correct headers
3. Check if `ghl_appointment_id` is being passed
4. Query: `SELECT * FROM appointments ORDER BY created_at DESC LIMIT 10`

### Wrong `created_source`

1. Check if n8n workflow is running
2. Verify `insert_appointment()` is using ON CONFLICT DO UPDATE
3. Check Edge Function logs for "skipped_existing" messages

### Slow Dashboard Queries

1. Check if indexes exist: `SELECT indexname FROM pg_indexes WHERE tablename = 'appointments'`
2. Run `ANALYZE` on affected tables
3. Consider materializing slow views

### Migration Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `cannot drop columns from view` | View has different columns | Add `DROP VIEW IF EXISTS ... CASCADE` before CREATE |
| `function name is not unique` | Multiple function signatures | Drop all versions first with dynamic query |
| `check constraint violated` | Existing data doesn't match | Normalize data before adding constraint |

---

## Environment Details

### Supabase Project

| Setting | Value |
|---------|-------|
| Project ID | `gamwimamcvgakcetdypm` |
| Region | (check dashboard) |
| Database Version | PostgreSQL 15+ |

### GHL Webhook Headers

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdhbXdpbWFtY3ZnYWtjZXRkeXBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNDM0NzAsImV4cCI6MjA4MjYxOTQ3MH0.CuhNBluIOX6bMukLuvnmtd6gCq1k8fTVAL-xRDcUbis
Content-Type: application/json
```

### Webhook Endpoints

| Webhook | URL |
|---------|-----|
| Appointment (unified) | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook` |

---

## Key Files Reference

| File | Purpose | When to Modify |
|------|---------|----------------|
| `docs/SCHEMA.md` | Complete DB schema | When tables/views change |
| `docs/DATA_DICTIONARY.md` | Raw vs calculated data | When formulas change |
| `docs/ARCHITECTURE.md` | Data flow documentation | When integrations change |
| `docs/WEBHOOKS.md` | Webhook setup guide | When endpoints change |
| `supabase/functions/ghl-appointment-webhook/index.ts` | Appointment webhook | When webhook logic changes |
| `supabase/migrations/*.sql` | Database changes | When schema changes |

---

## Testing Checklist

Before deploying changes:

- [ ] SQL runs without errors in Supabase SQL Editor
- [ ] Edge functions deploy successfully
- [ ] Webhook receives test payload correctly
- [ ] Views return expected data
- [ ] No orphaned records created
- [ ] Indexes exist for new query patterns
- [ ] Documentation updated

---

## Contact & Resources

- **Supabase Dashboard:** https://supabase.com/dashboard/project/gamwimamcvgakcetdypm
- **GHL Documentation:** https://highlevel.stoplight.io/
- **n8n Workflows:** (internal n8n instance)

---

## Appendix: SQL Snippets

### Check Table Health

```sql
-- Row counts by table
SELECT
    'leads' as table_name, COUNT(*) as rows FROM leads
UNION ALL SELECT 'tasks', COUNT(*) FROM tasks
UNION ALL SELECT 'appointments', COUNT(*) FROM appointments
UNION ALL SELECT 'reactivations', COUNT(*) FROM reactivations
UNION ALL SELECT 'ai_decisions', COUNT(*) FROM ai_decisions;
```

### Check Orphaned Records

```sql
-- Tasks without matching leads
SELECT COUNT(*) as orphaned_tasks
FROM tasks t
LEFT JOIN leads l ON t.contact_id = l.contact_id
WHERE l.contact_id IS NULL;

-- Appointments without matching leads
SELECT COUNT(*) as orphaned_appointments
FROM appointments a
LEFT JOIN leads l ON a.contact_id = l.contact_id
WHERE l.contact_id IS NULL;
```

### Check Index Usage

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### Check Constraint Status

```sql
SELECT
    conname as constraint_name,
    conrelid::regclass as table_name,
    contype as type
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY conrelid::regclass, conname;
```
