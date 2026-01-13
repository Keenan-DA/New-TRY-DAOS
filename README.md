# DA-OS (Dealer AI Operating System)

A comprehensive data platform for tracking AI-assisted automotive dealership operations, measuring performance metrics, and providing actionable insights for Customer Success teams.

## New Developer? Start Here

1. Read the **[Developer Guide](docs/DEVELOPER_GUIDE.md)** - Setup, workflows, and common tasks
2. Review the **[Data Dictionary](docs/DATA_DICTIONARY.md)** - All data fields and formulas
3. Explore the **[Architecture](docs/ARCHITECTURE.md)** - System design and data flows

---

## Overview

DA-OS integrates with:
- **GHL (GoHighLevel)** - CRM and appointment management
- **n8n** - Workflow automation (Drive AI 7.0, Reactivate Drive)
- **Supabase** - Database and edge functions

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   GHL CRM       │────►│  n8n Workflows  │────►│    Supabase     │
│                 │     │                 │     │                 │
│ • Contacts      │     │ • Drive AI 7.0  │     │ • PostgreSQL    │
│ • Appointments  │     │ • Reactivate    │     │ • Edge Functions│
│ • Calendars     │     │ • Lead Tracker  │     │ • Views/RPCs    │
└────────┬────────┘     └─────────────────┘     └────────┬────────┘
         │                                               │
         │              ┌─────────────────┐              │
         └─────────────►│  GHL Webhooks   │◄─────────────┘
                        │                 │
                        │ • Lead Created  │
                        │ • Appointments  │
                        │ • Messages      │
                        └─────────────────┘
```

## Key Features

### Data Tracking
- **Leads** - New inbound, database, service leads with source normalization
- **Tasks** - AI-generated follow-up tasks with completion tracking
- **Appointments** - AI vs human booking attribution
- **Reactivations** - Rep-instructed actions via Close the Loop

### Metrics & Views
- Speed to lead
- Response rates
- Show rates
- AI/Human booking ratio
- Rep performance breakdowns
- Lost opportunity estimation

---

## Project Structure

```
DA-OS/
├── README.md                         # This file
├── .gitignore                        # Ignored files
│
├── docs/                             # Documentation
│   ├── DEVELOPER_GUIDE.md            # 🚀 START HERE - Developer onboarding
│   ├── DATA_DICTIONARY.md            # All data fields & formulas
│   ├── ARCHITECTURE.md               # Data flow & system design
│   ├── SCHEMA.md                     # Complete database schema
│   ├── DASHBOARD_BLUEPRINT.md        # CS Dashboard specifications
│   ├── WEBHOOKS.md                   # Webhook setup guide
│   └── diagrams/
│       └── data-flow.html            # Visual architecture diagram
│
├── supabase/
│   ├── migrations/                   # SQL migrations (run in order)
│   │   ├── 002_appointment_upsert.sql
│   │   └── 003_critical_fixes.sql
│   └── functions/                    # Edge functions
│       └── ghl-appointment-webhook/
│           └── index.ts
│
└── data/                             # Local data (gitignored)
```

---

## Quick Start

### 1. Run Migrations (in order)

```bash
# In Supabase SQL Editor, run:
supabase/migrations/002_appointment_upsert.sql
supabase/migrations/003_critical_fixes.sql
```

### 2. Deploy Edge Functions

```bash
supabase functions deploy ghl-appointment-webhook
```

### 3. Configure GHL Webhooks

Set up TWO webhooks pointing to the same endpoint:

| Trigger | URL |
|---------|-----|
| Appointment Created | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook` |
| Appointment Status Changed | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook` |

See [docs/WEBHOOKS.md](docs/WEBHOOKS.md) for full setup instructions.

---

## Appointment Source Attribution

| Source | `created_source` | Counts As |
|--------|------------------|-----------|
| Drive AI 7.0 | `ai_automated` | AI |
| Reactivate Drive | `rep_instructed` | Human |
| GHL Calendar (manual) | `rep_manual` | Human |

**Deduplication Logic:**
- n8n workflows use `ON CONFLICT DO UPDATE` (authoritative)
- GHL webhook checks existence first (passive)
- Result: No duplicates, correct attribution

---

## Key Formulas

| Metric | Formula |
|--------|---------|
| **Speed to Lead** | `first_outbound_at - lead_date` (seconds) |
| **Closed Loop %** | `completed / (completed + overdue) × 100` |
| **Show Rate** | `showed / (showed + no_show) × 100` |
| **AI/Human Ratio** | `ai_booked / (rep_instructed + rep_manual)` |
| **Health Score** | `(loop × 0.4) + (clarity × 0.3) + (marking × 0.3)` |

See [docs/DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) for complete formula reference.

---

## Key Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `leads` | All contacts | `contact_id`, `location_id`, `speed_to_lead_seconds` |
| `tasks` | AI-created follow-ups | `task_id`, `completed`, `due_date` |
| `appointments` | Booked appointments | `created_source`, `outcome_status` |
| `reactivations` | Rep instructions | `action`, `instruction` |
| `ai_decisions` | AI decision audit log | `action`, `confidence` |

## Key Views

| View | Purpose | Key Metrics |
|------|---------|-------------|
| `v_appointment_stats` | Appointment metrics | `show_rate`, `ai_booked`, `human_booked` |
| `v_loop_closure_stats` | Task completion | `closed_loop_pct` |
| `v_health_score` | Adoption score | `adoption_score` (0-100) |
| `v_ai_human_ratio` | Booking attribution | `ai_human_ratio`, `balance_status` |
| `v_speed_to_lead` | Response times | `avg_speed`, `speed_bucket` |

---

## Documentation Index

| Document | Purpose |
|----------|---------|
| [Developer Guide](docs/DEVELOPER_GUIDE.md) | Onboarding, setup, common tasks |
| [Data Dictionary](docs/DATA_DICTIONARY.md) | All fields, formulas, data flow |
| [Architecture](docs/ARCHITECTURE.md) | System design, integrations |
| [Schema](docs/SCHEMA.md) | Complete database reference |
| [Dashboard Blueprint](docs/DASHBOARD_BLUEPRINT.md) | CS Dashboard specs |
| [Webhooks](docs/WEBHOOKS.md) | Webhook configuration |

---

## Environment

| Setting | Value |
|---------|-------|
| **Supabase Project** | `gamwimamcvgakcetdypm` |
| **Database** | PostgreSQL 15+ |
| **Schema Version** | 7.0.5+ |

---

## Recent Changes

- **2026-01-13:** Added `rep_manual` appointment source for GHL calendar bookings
- **2026-01-13:** Unified appointment webhook (handles both creation and status updates)
- **2026-01-13:** Added CHECK constraints and performance indexes
- **2026-01-13:** Reorganized repository structure

---

## Contributing

1. Create a feature branch
2. Make changes
3. Update relevant documentation
4. Test in Supabase SQL Editor
5. Submit PR with description of changes

See [Developer Guide](docs/DEVELOPER_GUIDE.md) for detailed instructions.
