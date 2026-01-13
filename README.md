# DA-OS (Dealer AI Operating System)

A comprehensive data platform for tracking AI-assisted automotive dealership operations, measuring performance metrics, and providing actionable insights for Customer Success teams.

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

## Project Structure

```
DA-OS/
├── docs/                          # Documentation
│   ├── ARCHITECTURE.md            # Data flow & system design
│   ├── SCHEMA.md                  # Database schema reference
│   ├── DASHBOARD_BLUEPRINT.md     # CS Dashboard specifications
│   ├── WEBHOOKS.md                # Webhook setup guide
│   └── diagrams/                  # Visual diagrams
│
├── supabase/
│   ├── migrations/                # SQL migrations
│   │   └── 002_appointment_upsert.sql
│   └── functions/                 # Edge functions
│       └── ghl-appointment-webhook/
│
└── data/                          # Local data (gitignored)
```

## Quick Start

### 1. Run Migrations
```sql
-- Run in Supabase SQL Editor
-- See supabase/migrations/ for files
```

### 2. Deploy Edge Functions
```bash
supabase functions deploy ghl-appointment-webhook
```

### 3. Configure GHL Webhooks
See [docs/WEBHOOKS.md](docs/WEBHOOKS.md) for setup instructions.

## Appointment Source Attribution

| Source | `created_source` | Counts As |
|--------|------------------|-----------|
| Drive AI 7.0 | `ai_automated` | AI |
| Reactivate Drive | `rep_instructed` | Human |
| GHL Calendar (manual) | `rep_manual` | Human |

## Key Tables

| Table | Purpose |
|-------|---------|
| `leads` | All contacts with lead type classification |
| `tasks` | AI-generated follow-up tasks |
| `appointments` | Booked appointments with source tracking |
| `reactivations` | Rep-instructed actions |
| `ai_decisions` | AI decision audit log |

## Key Views

| View | Purpose |
|------|---------|
| `v_dealerships` | Dealership reference data |
| `v_appointment_stats` | Appointment metrics by dealership |
| `v_ai_human_ratio` | AI vs human booking balance |
| `v_rep_appointment_breakdown` | Per-rep appointment metrics |
| `v_lost_opportunity` | Estimated missed appointments |

## Documentation

- [Architecture & Data Flow](docs/ARCHITECTURE.md)
- [Database Schema](docs/SCHEMA.md)
- [Dashboard Blueprint](docs/DASHBOARD_BLUEPRINT.md)
- [Webhook Setup](docs/WEBHOOKS.md)

## Environment

- **Supabase Project:** `gamwimamcvgakcetdypm`
- **Database Version:** 7.0.5+
