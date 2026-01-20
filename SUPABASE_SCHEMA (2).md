# DRIVE AI 7.0 - Complete Supabase Database Documentation

**Version:** 7.0.6
**Last Updated:** January 20, 2026
**Database Stats:** 7 Tables | 35 Views | 2 Materialized Views | 56 Functions | 6 Triggers | 69 Indexes

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Database Architecture](#database-architecture)
3. [Tables (7)](#tables)
4. [Views (37)](#views)
5. [Functions (56)](#functions)
6. [Triggers (6)](#triggers)
7. [Indexes (67)](#indexes)
8. [Key Formulas & Business Logic](#key-formulas--business-logic)
9. [Data Flow](#data-flow)
10. [Key Relationships](#key-relationships)

---

## System Overview

### What is Drive AI 7.0?

Drive AI is an automotive dealership AI assistant that:

1. **Engages Leads** - Automatically responds to new inbound leads via SMS/email in under 60 seconds
2. **Creates Tasks** - When AI needs human intervention, it creates tasks for sales reps
3. **Processes Instructions** - Reps provide follow-up instructions via "Reactivate Drive" (Close the Loop)
4. **Books Appointments** - AI can book appointments automatically or per rep instruction
5. **Tracks Everything** - All interactions are logged for accountability and reporting
6. **Proves Compounding** - Tracks aged lead conversions to prove pipeline value over time

### Data Sources

| Source | Webhook/Trigger | Data Created |
|--------|-----------------|--------------|
| GHL Contact Created | n8n workflow | `leads` record |
| GHL Outbound Message | n8n workflow | Updates `leads.first_outbound_at`, triggers speed calculation |
| GHL Inbound Response | n8n workflow | Updates `leads.first_response_at` |
| Drive AI Decision | n8n workflow | `ai_decisions` + `tasks` records |
| Reactivate Drive Form | n8n workflow | `reactivations` record, completes tasks |
| GHL Appointment Created | n8n workflow | `appointments` record |
| GHL Appointment Outcome | n8n workflow | Updates `appointments.outcome_status` |

### Connection Details

```
URL: https://gamwimamcvgakcetdypm.supabase.co
API Key: sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1

Headers for REST API:
  apikey: [API_KEY]
  Content-Type: application/json
```

---

## Database Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DRIVE AI 7.0 DATABASE                             │
│                                                                             │
│  7 Tables | 33 Views | 56 Functions | 6 Triggers | 67 Indexes              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │    leads     │────▶│    tasks     │────▶│ reactivations│                │
│  │  (contacts)  │     │ (AI-created) │     │ (rep input)  │                │
│  └──────────────┘     └──────────────┘     └──────────────┘                │
│         │                    │                    │                         │
│         │                    │                    │                         │
│         ▼                    ▼                    ▼                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │ appointments │     │ ai_decisions │     │task_completions│              │
│  │  (bookings)  │     │ (AI actions) │     │  (junction)  │                │
│  └──────────────┘     └──────────────┘     └──────────────┘                │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    lead_source_dictionary                             │  │
│  │                  (source normalization lookup)                        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Tables

### 1. leads

**Purpose:** Master table of all contacts/leads entering the system. Tracks the complete lifecycle from first contact through conversion or removal.

**Source:** GHL "Contact Created" webhook → n8n "Lead Tracker" workflow

**Row Count:** ~10,000+ (growing)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NO | `uuid_generate_v4()` | Primary key |
| `contact_id` | text | NO | - | **GHL contact ID** (unique identifier from GoHighLevel) |
| `location_id` | text | NO | - | **GHL sub-account ID** (identifies the dealership) |
| `lead_type` | text | NO | `'new_inbound'` | Classification: `new_inbound`, `aged_upload`, `rep_created` |
| `lead_source` | text | YES | - | Raw source from GHL (e.g., "Cars.com", "Facebook Lead") |
| `lead_source_normalized` | text | YES | - | Standardized source name (via dictionary) |
| `lead_source_category` | text | YES | - | Category: `Third-Party Listing`, `Social Media`, `OEM`, etc. |
| `lead_tags` | ARRAY | YES | - | Array of GHL tags on the contact |
| `dealership_name` | text | YES | - | Human-readable dealership name |
| `dealership_timezone` | text | YES | - | Timezone for scheduling (e.g., "America/Chicago") |
| `lead_name` | text | YES | - | Full name of lead |
| `lead_first_name` | text | YES | - | First name only |
| `lead_last_name` | text | YES | - | Last name only |
| `lead_phone` | text | YES | - | Phone number |
| `lead_email` | text | YES | - | Email address |
| `lead_date` | timestamptz | YES | `now()` | When lead entered our tracking system |
| `original_lead_date` | timestamptz | YES | - | GHL's `dateAdded` (for aged leads, differs from lead_date) |
| `first_outbound_at` | timestamptz | YES | - | **When AI sent first message** |
| `first_outbound_type` | text | YES | - | Channel: `sms`, `email`, `chat` |
| `first_response_at` | timestamptz | YES | - | **When lead first replied** |
| `responded` | boolean | YES | `false` | Has lead ever responded? |
| `time_to_outbound_minutes` | integer | YES | - | Minutes from lead_date → first_outbound |
| `time_to_response_minutes` | integer | YES | - | Minutes from first_outbound → first_response |
| `speed_to_lead_seconds` | integer | YES | - | **Seconds from lead_date → first_outbound** (auto-calculated by trigger) |
| `status` | text | YES | `'active'` | Lifecycle: `active`, `converted`, `removed` |
| `converted_at` | timestamptz | YES | - | When status changed to converted |
| `removed_at` | timestamptz | YES | - | When status changed to removed |
| `removed_by` | text | YES | - | Who removed: `ai`, `rep`, `lead` (opt-out) |
| `remove_reason` | text | YES | - | Reason for removal |
| `task_count` | integer | YES | `0` | Number of tasks created for this lead |
| `reactivation_count` | integer | YES | `0` | Number of reactivations submitted |
| `appointment_count` | integer | YES | `0` | Number of appointments booked |
| `first_appointment_at` | timestamptz | YES | - | When first appointment was booked |
| `appointment_booked` | boolean | YES | `false` | Has any appointment been booked? |
| `created_at` | timestamptz | YES | `now()` | Record creation timestamp |
| `updated_at` | timestamptz | YES | `now()` | Last update timestamp |

**Key Business Logic:**
- `lead_type` determines priority: `new_inbound` > `rep_created` > `aged_upload`
- `speed_to_lead_seconds` is auto-calculated by trigger when `first_outbound_at` is set
- Speed calculation excludes: walk-ins, phone-ups, and after-hours leads (8pm-8am)
- `removed_by = 'lead'` indicates an opt-out (STOP message)

**Indexes:**
- `idx_leads_contact_id` (UNIQUE)
- `idx_leads_location_id`
- `idx_leads_lead_date`
- `idx_leads_status`
- `idx_leads_lead_type`
- `idx_leads_responded`
- `idx_leads_appointment_booked`
- `idx_leads_speed_to_lead`
- `idx_leads_location_lead_date`

---

### 2. tasks

**Purpose:** Tasks created by Drive AI when human intervention is needed. This is the "handoff" from AI to human rep.

**Source:** Drive AI 7.0 workflow when AI determines rep action is needed

**Row Count:** ~5,000+

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NO | `uuid_generate_v4()` | Primary key |
| `task_id` | text | NO | - | **n8n traceId** (unique, used for upsert) |
| `ghl_task_id` | text | YES | - | GHL's internal task ID |
| `location_id` | text | NO | - | Dealership identifier |
| `dealership_name` | text | YES | - | Dealership name |
| `dealership_address` | text | YES | - | Physical address |
| `dealership_hours` | text | YES | - | Operating hours |
| `dealership_timezone` | text | YES | - | Timezone |
| `contact_id` | text | NO | - | **FK to leads.contact_id** |
| `lead_name` | text | YES | - | Lead's name |
| `lead_first_name` | text | YES | - | First name |
| `lead_phone` | text | YES | - | Phone |
| `lead_email` | text | YES | - | Email |
| `lead_tags` | text | YES | - | Tags as string |
| `lead_type` | text | YES | - | Copied from leads table |
| `title` | text | NO | `'Follow-up Required'` | Task title |
| `description` | text | YES | - | Detailed task description |
| `due_date` | timestamptz | YES | - | When task should be completed |
| `assigned_rep_id` | text | YES | - | **GHL user ID of assigned rep** |
| `assigned_rep_name` | text | YES | - | Rep's name |
| `trigger_action` | text | YES | - | What AI action triggered this task |
| `also_task` | boolean | YES | `false` | Was this a dual task+follow-up? |
| `ai_decision_id` | uuid | YES | - | FK to ai_decisions table |
| `lead_language` | text | YES | - | Detected language |
| `lead_last_message` | text | YES | - | Last message from lead |
| `drive_context` | text | YES | - | AI's conversation summary |
| `completed` | boolean | YES | `false` | **Has task been completed?** |
| `completed_at` | timestamptz | YES | - | When completed |
| `completed_by_reactivation_id` | uuid | YES | - | **FK to reactivations.id** |
| `task_created_at` | timestamptz | YES | - | When task was created in GHL |
| `created_at` | timestamptz | YES | `now()` | Supabase record creation |
| `updated_at` | timestamptz | YES | `now()` | Last update |
| `source_workflow` | text | YES | `'drive_ai_7'` | n8n workflow that created this |
| `raw_data` | jsonb | YES | - | Complete raw payload |

**Key Business Logic:**
- Tasks can ONLY be completed via a reactivation (submitting "Close the Loop" form)
- `completed_by_reactivation_id` links to the reactivation that closed this task
- A single reactivation can close multiple tasks (bulk completion)

**Indexes:**
- `idx_tasks_task_id` (UNIQUE)
- `idx_tasks_location_id`
- `idx_tasks_contact_id`
- `idx_tasks_completed`
- `idx_tasks_assigned_rep_id`
- `idx_tasks_due_date`
- `idx_tasks_created_at`
- `idx_tasks_location_completed`

---

### 3. reactivations

**Purpose:** Stores rep instructions ("Close the Loop" submissions) and the AI's resulting action. This is the human → AI handoff.

**Source:** "Reactivate Drive" workflow triggered by rep form submission

**Row Count:** ~3,000+

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NO | `uuid_generate_v4()` | Primary key |
| `execution_id` | text | YES | - | n8n execution ID |
| `location_id` | text | NO | - | Dealership identifier |
| `dealership_name` | text | YES | - | Dealership name |
| `dealership_hours` | text | YES | - | Operating hours |
| `dealership_timezone` | text | YES | - | Timezone |
| `contact_id` | text | NO | - | **FK to leads.contact_id** |
| `lead_name` | text | YES | - | Lead's name |
| `lead_first_name` | text | YES | - | First name |
| `lead_phone` | text | YES | - | Phone |
| `lead_email` | text | YES | - | Email |
| `lead_type` | text | YES | - | Copied from leads |
| `assigned_rep_id` | text | YES | - | **Rep who submitted** |
| `rep_name` | text | YES | - | Rep's name |
| `instruction` | text | YES | - | **Cleaned instruction text** |
| `instruction_raw` | text | YES | - | Original instruction before cleaning |
| `instruction_length` | integer | YES | - | Character count |
| `instruction_word_count` | integer | YES | - | Word count |
| `action` | text | YES | - | **AI decision: `follow_up`, `appointment`, `remove`** |
| `follow_up_message` | text | YES | - | If action=follow_up: the AI-generated message |
| `follow_up_date` | timestamptz | YES | - | When to send the follow-up |
| `appointment_type` | text | YES | - | If action=appointment: type of appointment |
| `appointment_time` | timestamptz | YES | - | Scheduled appointment time |
| `appointment_summary` | text | YES | - | Appointment notes |
| `ghl_appointment_id` | text | YES | - | GHL appointment ID |
| `drive_context` | text | YES | - | AI conversation context |
| `tasks_completed_count` | integer | YES | `0` | How many tasks this closed |
| `reactivated_at` | timestamptz | YES | `now()` | **When rep submitted** |
| `created_at` | timestamptz | YES | `now()` | Record creation |
| `updated_at` | timestamptz | YES | `now()` | Last update |
| `source_workflow` | text | YES | `'reactivate_drive'` | n8n workflow |
| `raw_data` | jsonb | YES | - | Complete raw payload |

**Key Business Logic:**
- `action = 'remove'` here means **REP-initiated removal** (vs AI removal in ai_decisions)
- The AI uses the `instruction` to generate `follow_up_message` or book `appointment`
- Instruction quality is scored based on Context + Action + Timing patterns

**Indexes:**
- `idx_reactivations_location_id`
- `idx_reactivations_contact_id`
- `idx_reactivations_assigned_rep_id`
- `idx_reactivations_action`
- `idx_reactivations_reactivated_at`

---

### 4. appointments

**Purpose:** All booked appointments, whether AI-automated or rep-instructed. Tracks outcomes (showed/no-show).

**Source:** Drive AI 7.0 + Reactivate Drive + GHL Appointment webhooks

**Row Count:** ~2,000+

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NO | `uuid_generate_v4()` | Primary key |
| `ghl_appointment_id` | text | YES | - | **GHL's appointment ID** |
| `trace_id` | text | YES | - | n8n trace ID |
| `calendar_id` | text | YES | - | GHL calendar ID |
| `location_id` | text | NO | - | Dealership identifier |
| `dealership_name` | text | YES | - | Dealership name |
| `dealership_address` | text | YES | - | Address |
| `dealership_hours` | text | YES | - | Operating hours |
| `dealership_timezone` | text | YES | - | Timezone |
| `contact_id` | text | NO | - | **FK to leads.contact_id** |
| `lead_name` | text | YES | - | Lead's name |
| `lead_first_name` | text | YES | - | First name |
| `lead_phone` | text | YES | - | Phone |
| `lead_email` | text | YES | - | Email |
| `lead_type` | text | YES | - | Lead classification |
| `assigned_rep_id` | text | YES | - | **Assigned rep GHL ID** |
| `assigned_rep_name` | text | YES | - | Rep name |
| `title` | text | YES | - | Appointment title |
| `appointment_type` | text | YES | - | Type: Sales, Service, Test Drive, etc. |
| `appointment_time` | timestamptz | YES | - | **Scheduled date/time** |
| `appointment_summary` | text | YES | - | Notes/summary |
| `appt_valid` | boolean | YES | `true` | Is appointment still valid? |
| `status` | text | YES | - | GHL status |
| `appointment_status` | text | YES | - | GHL appointment status |
| `outcome_status` | text | YES | `'pending'` | **`pending`, `showed`, `no_show`, `cancelled`** |
| `outcome_recorded_at` | timestamptz | YES | - | When outcome was recorded |
| `outcome_recorded_by` | text | YES | - | Who recorded outcome |
| `follow_up_after_outcome` | text | YES | - | Follow-up notes after no-show |
| `recovery_reactivation_id` | uuid | YES | - | FK to reactivation that recovered this no-show |
| `created_source` | text | YES | - | **`ai_automated` or `rep_instructed`** |
| `source_workflow` | text | YES | - | n8n workflow that created this |
| `reactivation_id` | uuid | YES | - | FK to reactivations (if rep-instructed) |
| `appointment_created_at` | timestamptz | YES | `now()` | When created in GHL |
| `created_at` | timestamptz | YES | `now()` | Supabase record creation |
| `updated_at` | timestamptz | YES | `now()` | Last update |
| `raw_data` | jsonb | YES | - | Complete raw payload |

**Key Business Logic:**
- `created_source` is critical for AI vs Human appointment attribution
- `outcome_status = 'pending'` + `appointment_time < NOW()` = unmarked appointment
- `follow_up_after_outcome` indicates a no-show has been "worked"

**Indexes:**
- `idx_appointments_ghl_id`
- `idx_appointments_location_id`
- `idx_appointments_contact_id`
- `idx_appointments_appointment_time`
- `idx_appointments_outcome_status`
- `idx_appointments_created_source`
- `idx_appointments_assigned_rep_id`

---

### 5. ai_decisions

**Purpose:** Logs every decision made by Drive AI (task creation, appointment booking, follow-up, removal).

**Source:** Drive AI 7.0 decision node

**Row Count:** ~8,000+

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NO | `uuid_generate_v4()` | Primary key |
| `execution_id` | text | YES | - | n8n execution ID |
| `trace_id` | text | YES | - | n8n trace ID |
| `location_id` | text | NO | - | Dealership identifier |
| `dealership_name` | text | YES | - | Dealership name |
| `contact_id` | text | NO | - | FK to leads.contact_id |
| `lead_name` | text | YES | - | Lead's name |
| `lead_phone` | text | YES | - | Phone |
| `lead_email` | text | YES | - | Email |
| `action` | text | NO | - | **`task`, `appointment`, `follow_up`, `remove`** |
| `reason` | text | YES | - | AI's explanation for decision |
| `confidence` | numeric | YES | - | Confidence score (0-1) |
| `trigger_message` | text | YES | - | The message that triggered this decision |
| `conversation_length` | integer | YES | - | Number of messages in conversation |
| `conversation_summary` | text | YES | - | AI summary of conversation |
| `initiated_by` | text | YES | `'ai'` | Always 'ai' for this table |
| `source_workflow` | text | YES | `'drive_ai_7'` | Workflow name |
| `decided_at` | timestamptz | YES | `now()` | When decision was made |
| `created_at` | timestamptz | YES | `now()` | Record creation |

**Key Business Logic:**
- `action = 'remove'` here means **AI-initiated removal** (opt-out detected, invalid lead, etc.)
- Distinguished from rep-initiated removal in `reactivations.action = 'remove'`

**Indexes:**
- `idx_ai_decisions_location_id`
- `idx_ai_decisions_contact_id`
- `idx_ai_decisions_action`
- `idx_ai_decisions_decided_at`

---

### 6. task_completions

**Purpose:** Junction table linking tasks to the reactivations that completed them. Tracks completion metrics.

**Source:** Created when a reactivation closes tasks

**Row Count:** ~3,000+

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NO | `uuid_generate_v4()` | Primary key |
| `task_id` | uuid | NO | - | **FK to tasks.id** |
| `reactivation_id` | uuid | NO | - | **FK to reactivations.id** |
| `was_overdue` | boolean | YES | `false` | Was task overdue when completed? |
| `days_overdue` | integer | YES | `0` | How many days overdue |
| `hours_to_complete` | numeric | YES | - | **Hours from task creation to completion** |
| `completed_at` | timestamptz | YES | `now()` | When completed |

**Key Business Logic:**
- One reactivation can complete multiple tasks (many-to-many)
- `hours_to_complete` is used for rep response time metrics

**Indexes:**
- `idx_task_completions_task_id`
- `idx_task_completions_reactivation_id`

---

### 7. lead_source_dictionary

**Purpose:** Lookup table for normalizing raw lead sources to standardized names and categories.

**Source:** Manually maintained

**Row Count:** ~50

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | integer | NO | auto-increment | Primary key |
| `normalized_name` | text | NO | - | **Standardized source name** (e.g., "Cars.com") |
| `category` | text | NO | - | **Category** (e.g., "Third-Party Listing") |
| `match_patterns` | text | NO | - | **Regex/patterns to match** |
| `priority` | integer | YES | `100` | Lower = higher priority |
| `created_at` | timestamptz | YES | `now()` | Record creation |

**Categories:**
| Category | Example Sources |
|----------|-----------------|
| Third-Party Listing | Cars.com, AutoTrader, CarGurus, TrueCar |
| Social Media | Facebook, Instagram |
| OEM | GM Leads, Ford Direct, Toyota Engage |
| Website | Direct website forms |
| Traditional/Offline | Walk-In, Phone-Up |
| Other | Unknown sources |

---

## Views

### View Architecture (37 Views)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DRIVE AI VIEW ARCHITECTURE (37 Views)                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  TIER 1: FOUNDATION (3 views)                                               │
│  v_dealerships          v_reps          v_source_map                        │
│                                                                             │
│  TIER 2: LEAD PIPELINE (8 views)                                            │
│  v_lead_pipeline        v_lead_funnel         v_lead_funnel_summary         │
│  v_funnel_metrics       v_conversion_funnel   v_conversion_by_source        │
│  v_source_performance   v_pipeline_funnel ⭐ NEW                            │
│                                                                             │
│  TIER 3: SPEED-TO-LEAD (1 view)                                             │
│  v_speed_metrics                                                            │
│                                                                             │
│  TIER 4: TASKS & LOOP CLOSURE (3 views)                                     │
│  v_loop_closure_stats   v_overdue_tasks       v_task_efficiency             │
│                                                                             │
│  TIER 5: INSTRUCTION QUALITY (4 views)                                      │
│  v_instruction_clarity  v_rep_instruction_quality                           │
│  v_instruction_log      v_instruction_quality (legacy)                      │
│                                                                             │
│  TIER 6: APPOINTMENTS (6 views)                                             │
│  v_appointment_stats    v_rep_appointment_stats   v_ai_human_ratio          │
│  v_unmarked_appointments v_upcoming_appointments                            │
│  v_rep_appointment_breakdown ⭐ NEW                                         │
│                                                                             │
│  TIER 7: NO-SHOW RECOVERY (1 view)                                          │
│  v_no_shows                                                                 │
│                                                                             │
│  TIER 8: REP PERFORMANCE (2 views)                                          │
│  v_rep_complete_scorecard   v_instruction_quality_by_rep (legacy)           │
│                                                                             │
│  TIER 9: HEALTH & ADOPTION (2 views)                                        │
│  v_health_score         v_health_trend                                      │
│                                                                             │
│  TIER 10: COMPOUNDING PROOF (3 views)                                       │
│  v_compounding_metrics  v_aged_lead_conversions   v_pipeline_growth         │
│                                                                             │
│  TIER 11: SUMMARIES & TRENDS (2 views)                                      │
│  v_daily_summary        v_metrics_monthly                                   │
│                                                                             │
│  TIER 12: CS PORTFOLIO MANAGEMENT (1 view)                                  │
│  v_cs_account_health                                                        │
│                                                                             │
│  TIER 13: LOST OPPORTUNITY ANALYSIS (1 view) ⭐ NEW                         │
│  v_lost_opportunity                                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Core Reference Views

#### v_dealerships
**Purpose:** List of all dealerships for dropdown filters.

**Columns:** `location_id`, `dealership_name`, `timezone`

**Used By:** All dashboard dealership dropdowns

---

#### v_reps
**Purpose:** List of all sales reps with their assigned_rep_id, name, and dealership.

**Columns:** `assigned_rep_id`, `location_id`, `rep_name`, `dealership_name`

**Used By:** Rep dropdown filters

---

#### v_source_map
**Purpose:** Shows how raw sources map to normalized names for debugging.

**Columns:** `lead_source`, `lead_source_normalized`, `lead_source_category`, `lead_count`

---

### Pipeline & Funnel Views

#### v_lead_pipeline
**Purpose:** Complete lead journey for each lead.

**Key Columns:**
- `outbound_sent` - Boolean: did AI send a message?
- `speed_to_lead_seconds` - Time from lead entry to first outbound
- `responded` - Did lead reply?
- `appointment_booked` - Was appointment scheduled?
- `days_to_appointment` - Days from lead entry to first appointment
- `showed` / `no_showed` - Appointment outcome

---

#### v_funnel_metrics
**Purpose:** Detailed funnel with speed-to-lead metrics, properly filtered.

**Exclusions:**
- Excludes `Walk-In` and `Phone-Up` sources from speed calculations
- Excludes after-hours leads (8pm-8am) from speed calculations
- Only includes `new_inbound` leads

**Key Metrics:**
- `avg_speed_seconds` / `avg_speed_minutes`
- `pct_under_1_min` / `pct_under_5_min`
- `opt_out_rate`
- `booking_rate`

---

#### v_conversion_funnel
**Purpose:** Aggregate funnel metrics by dealership.

**Metrics:**
| Metric | Calculation |
|--------|-------------|
| `pct_outbound` | Outbound sent / Total leads |
| `pct_responded` | Responded / Outbound sent |
| `pct_appt_from_response` | Appointments / Responded |
| `show_rate` | Showed / (Showed + No-show) |
| `lead_to_show_rate` | Showed / Total leads |

---

#### v_conversion_by_source
**Purpose:** Funnel metrics broken down by lead source.

**Answers:**
- Which source has best response rate?
- Which source converts to appointments best?
- Which source has fastest speed-to-lead?

---

#### v_source_performance
**Purpose:** Source performance with quality scoring.

**Quality Score Formula:**
```
Quality Score = (response_rate × 40) + (appt_rate × 30) + (show_rate × 30)
```

---

#### v_pipeline_funnel ⭐ (NEW Dec 31, 2025)
**Purpose:** Complete lead-to-show conversion funnel with proper opt-out and engagement tracking.

**Key Features:**
- Tracks full journey: Lead → Outbound → Response → Engaged → Booked → Showed
- Separates opt-outs (AI removes) from rep removes
- Speed-to-lead with proper exclusions (only valid automated sends ≤10 min)
- Booking rate calculated on engaged responses (excluding opt-outs)

**Columns:**
| Column | Description |
|--------|-------------|
| `total_new_inbound` | New inbound leads |
| `outbound_sent` | Leads that received initial outbound message |
| `outbound_rate` | % of leads that got outbound |
| `avg_speed_to_lead_seconds` | Average speed (excludes >10 min manual sends) |
| `avg_speed_to_lead_minutes` | Same in minutes |
| `speed_sample_size` | How many leads included in speed calc |
| `total_responses` | All leads that responded |
| `reply_rate` | % of outbound that got any response |
| `opt_outs` | AI-detected removes (STOP messages, invalid) from `ai_decisions` |
| `rep_removed` | Rep-instructed removes from `reactivations` |
| `engaged_responses` | Responded minus opt-outs |
| `appointments_booked` | Leads with actual appointments (via join) |
| `booking_rate` | % of engaged that booked (excludes opt-outs) |
| `total_appointments` | All appointments for location |
| `past_appointments` | Appointments that have occurred |
| `marked_appointments` | Past appointments with outcome recorded |
| `unmarked_appointments` | Past appointments still pending |
| `showed` | Appointments marked showed |
| `no_shows` | Appointments marked no-show |
| `show_rate` | % showed of (showed + no_show) |
| `marking_rate` | % of past appointments marked |

**Important Notes:**
- `opt_outs` from `ai_decisions.action = 'remove'` (AI-initiated)
- `rep_removed` from `reactivations.action = 'remove'` (rep-instructed)
- `appointments_booked` uses actual join to appointments table (not unreliable flag)
- Speed excludes overnight leads and manual sends (>10 min)

---

### Speed-to-Lead Views

#### v_speed_metrics
**Purpose:** Speed-to-lead metrics by dealership.

**Columns:**
- `avg_speed_to_lead_sec` / `avg_speed_to_lead_min`
- `median_speed_to_lead_sec`
- `under_1_min` / `under_5_min` counts and percentages
- `response_rate`

---

### Task & Loop Closure Views

#### v_loop_closure_stats ⭐ (Updated Dec 31, 2025)
**Purpose:** Task completion metrics by dealership.

**Key Metrics:**
- `total_tasks` / `completed_tasks` / `pending_tasks` / `overdue_tasks` / `pending_not_due`
- `closed_loop_pct` - % of **accountable** tasks completed (see formula below)
- `avg_hours_to_close` / `median_hours_to_close`
- `closed_while_overdue` - Tasks closed after they were already overdue
- `remove_pct` - % of reactivations that resulted in removal

**Loop Closure Formula (Updated Dec 31, 2025):**
```
closed_loop_pct = completed_tasks / (completed_tasks + overdue_tasks) × 100
```
> **Note:** Only counts "accountable" tasks - tasks that are either completed OR past due. Tasks not yet due don't penalize the score.

---

#### v_overdue_tasks
**Purpose:** List of all uncompleted tasks past their due date.

**Includes:**
- `hours_overdue` / `days_overdue`
- `urgency` - CRITICAL (>7 days), HIGH (>3 days), MEDIUM (>1 day), LOW

---

#### v_task_efficiency
**Purpose:** Tasks per lead ratio over time (monthly).

**Compounding Status:**
| Status | Threshold |
|--------|-----------|
| `COMPOUNDING` | ≥1.5 tasks per lead |
| `GOOD` | ≥1.0 tasks per lead |
| `STARTING` | ≥0.8 tasks per lead |
| `LOW` | <0.8 tasks per lead |

---

### Instruction Quality Views

#### v_instruction_clarity ⭐ (Updated Dec 30, 2025)
**Purpose:** Individual instruction-level quality scoring with EXPANDED regex patterns.

**Quality Components (regex-based):**

| Component | Patterns Detected |
|-----------|-------------------|
| `has_context` | asked, wanted, interested, looking, trade, vehicle, car, truck, suv, pricing, price, quote, offer, deal, sold, bought, test drive, called, voicemail, no answer, left message, spoke, mentioned, said, told, visit, come in, stop by, credit, approved, financing, co-sign, down payment, monthly, payment, inventory, stock, appointment, scheduled, waiting, ready, hot, warm, cold, serious, motivated, hesitant, concerned, question, issue, problem, help, needs, wants, budget, range, lease, loan, purchase, **50+ vehicle makes/models** |
| `has_action` | call, text, follow, send, schedule, reach, contact, see if, find out, try to, ask, let know, make aware, remind, check, confirm, book, set up, arrange, get back, respond, reply, message, email, notify, engage, stop, don't, do not, cease, continue, keep, update, inform, touch base, circle back, ping, nudge, push, offer, present, show, demo, walk through, explain, discuss, talk, speak, meet, visit, invite, bring in, get in, have come |
| `has_timing` | today, tomorrow, morning, afternoon, evening, tonight, week, monday-sunday, month names, time patterns (HH:MM, X am/pm), next, later, soon, asap, now, immediately, hours, days, end of, first thing, eod, eow, this week, next week, couple, few, within, right away, when available |

**Clarity Levels:**
| Level | Criteria |
|-------|----------|
| `complete` | Has ALL THREE components (Context + Action + Timing) |
| `partial` | Has TWO of three |
| `incomplete` | Has ONE or zero |
| `empty` | No instruction provided |

**Current Distribution (Dec 30, 2025):**
- Complete: 564 (49%)
- Partial: 333 (29%)
- Incomplete: 196 (17%)
- Empty: 70 (6%)

---

#### v_rep_instruction_quality
**Purpose:** Instruction quality aggregated by rep.

**Key Metrics:**
- `total_instructions`
- `complete_count` / `partial_count` / `incomplete_count` / `empty_count`
- `clarity_pct` - % complete (of non-empty)
- `missing_context` / `missing_action` / `missing_timing` - Counts of each missing element
- `avg_instruction_length`

---

#### v_instruction_log
**Purpose:** Full instruction log with AI outcomes for the Instruction Log tab.

**Includes:**
- Rep instruction
- AI action (`follow_up`, `appointment`, `remove`)
- Follow-up message and date (if follow_up)
- Appointment details (if appointment)
- Clarity scoring
- Display-formatted labels

---

### Appointment Views

#### v_appointment_stats
**Purpose:** Appointment metrics by dealership.

**Key Metrics:**
- `ai_booked` / `rep_booked` - Attribution
- `showed` / `no_shows` / `cancelled` / `pending` / `unmarked`
- `show_rate` = showed / (showed + no_shows) × 100
- `marking_pct` - % of past appointments with outcomes recorded
- `no_shows_worked` / `no_shows_unworked`
- `no_show_recovery_pct`

---

#### v_ai_human_ratio
**Purpose:** Balance between AI and human-booked appointments.

**Balance Status:**
| Status | Ratio |
|--------|-------|
| `BALANCED` | 0.8-1.2 |
| `STAFF_UNDERPERFORMING` | <0.5 |
| `AI_UNDERUTILIZED` | >2.0 |

---

#### v_upcoming_appointments
**Purpose:** Future appointments not yet occurred.

**Columns:** `hours_until`, `days_until`

---

#### v_unmarked_appointments
**Purpose:** Past appointments with `outcome_status = 'pending'`.

**Filter Logic:**
```sql
WHERE outcome_status = 'pending' AND appointment_time < NOW()
```
> **Note:** Only shows appointments that have already occurred but haven't been marked. Future appointments with 'pending' status are expected and not included.

**Urgency Levels:**
- CRITICAL (>5 days unmarked)
- HIGH (>3 days)
- MEDIUM (>1 day)
- NEW

---

#### v_no_shows
**Purpose:** All no-show appointments with recovery tracking.

**Recovery Status:**
| Status | Criteria |
|--------|----------|
| `RECOVERED` | Has recovery_reactivation_id |
| `IN_PROGRESS` | Has follow_up_after_outcome |
| `UNWORKED` | No follow-up recorded |

---

#### v_rep_appointment_breakdown ⭐ (NEW Dec 31, 2025)
**Purpose:** Per-rep appointment metrics with marking rate and show rate. Used in CS Dashboard rep appointment table.

**Columns:**
| Column | Description |
|--------|-------------|
| `location_id` | Dealership identifier |
| `assigned_rep_id` | Rep's GHL user ID |
| `rep_name` | Rep's name (or "Unassigned") |
| `dealership_name` | Dealership name |
| `total_appointments` | All appointments for this rep |
| `ai_booked` | Appointments from `created_source = 'ai_automated'` |
| `rep_booked` | Appointments from `created_source = 'rep_instructed'` |
| `past_appointments` | Appointments that have occurred |
| `marked_appointments` | Past appointments with outcome recorded |
| `unmarked_appointments` | Past appointments still pending |
| `marking_rate` | % of past appointments marked |
| `showed` | Appointments marked showed |
| `no_shows` | Appointments marked no-show |
| `cancelled` | Appointments marked cancelled |
| `show_rate` | % showed of (showed + no_show) |
| `status` | Auto-calculated flag |

**Status Values:**
| Status | Trigger |
|--------|---------|
| `NO_PAST_APPTS` | No past appointments to mark |
| `LOW_MARKING` | Marking rate < 50% |
| `LOW_SHOW_RATE` | Show rate < 50% (when marking is OK) |
| `OK` | Both metrics acceptable |

**Use Case:** CS team identifies which reps aren't marking appointments or have low show rates.

---

### Rep Performance Views

#### v_rep_complete_scorecard ⭐ (Updated Dec 31, 2025)
**Purpose:** Comprehensive rep performance metrics. **This is the main rep leaderboard view.**

**Metrics Included:**
- **Task Performance:** `total_tasks`, `completed_tasks`, `overdue_tasks`, `closed_loop_pct`
- **Speed:** `avg_hours_to_close`, `median_hours_to_close`
- **Instruction Quality:** `complete_instructions`, `partial_instructions`, `low_instructions`, `clarity_pct`
- **Appointments:** `total_appointments`, `rep_booked_appointments`, `showed`, `no_shows`, `unworked_no_shows`, `show_rate`
- **Remove Rate:** `remove_pct`

**Loop Closure Formula (Updated Dec 31, 2025):**
```
closed_loop_pct = completed_tasks / (completed_tasks + overdue_tasks) × 100
```
> **Note:** Only counts "accountable" tasks per rep. Tasks not yet due don't penalize.

**Performance Status (auto-calculated):**
| Status | Criteria |
|--------|----------|
| `EXCELLENT` | ≥85% loop closure AND ≥70% clarity |
| `GOOD` | ≥70% loop closure AND ≥50% clarity |
| `FAIR` | ≥50% loop closure |
| `NEEDS_COACHING` | <50% loop closure |

**Coaching Recommendation:** Auto-generated text focusing on lowest-performing metric (now includes overdue task count)

---

#### v_rep_appointment_stats
**Purpose:** Appointment metrics per rep.

---

### Health Score Views

#### v_health_score ⭐ MATERIALIZED VIEW (Updated Jan 20, 2026)
**Purpose:** Overall system health/adoption score per dealership.

**Type:** MATERIALIZED VIEW (pre-computed for performance, requires periodic refresh)

**Component Scores:**
| Score | Weight | Calculation |
|-------|--------|-------------|
| `closed_loop_score` | 40% | Completed tasks / (Completed + Overdue) × 100 |
| `clarity_score` | 30% | Complete instructions / Non-empty instructions × 100 |
| `marking_score` | 30% | Marked appointments / Past appointments × 100 |

**Adoption Score Formula:**
```
Adoption Score = (closed_loop_score × 0.40) + (clarity_score × 0.30) + (marking_score × 0.30)
```

**Clarity Score Calculation (Fixed Jan 20, 2026):**
```sql
clarity_score = complete_instructions / non_empty_instructions × 100
```
> **Important:** Clarity is calculated by aggregating from `v_instruction_clarity` per location. Only non-empty instructions are counted in the denominator. This was fixed in v7.0.6 to properly pull from the instruction clarity view.

**Loop Closure Formula:**
```
closed_loop_score = completed_tasks / (completed_tasks + overdue_tasks) × 100
```
> **Note:** Only counts "accountable" tasks. Tasks not yet due don't penalize the score.

**Health Status (auto-calculated):**
| Status | Score Range |
|--------|-------------|
| `EXCELLENT` | ≥80 |
| `GOOD` | 60-79 |
| `FAIR` | 40-59 |
| `CRITICAL` | <40 |

**Columns:**
- `location_id`, `dealership_name`
- `total_tasks`, `completed_tasks`, `overdue_tasks`, `closed_loop_score`
- `total_instructions`, `complete_instructions`, `empty_instructions`, `clarity_score`
- `past_appointments`, `marked_appointments`, `unmarked_appointments`, `marking_score`

**Refresh Command:**
```sql
REFRESH MATERIALIZED VIEW v_health_score;
```

---

#### v_health_trend ⭐ (Updated Dec 31, 2025)
**Purpose:** Weekly health score trend over the past 90 days.

**Columns:**
- `location_id`, `week`
- `tasks_created`, `tasks_completed`, `tasks_overdue`, `loop_closure_pct`
- `total_instructions`, `complete_instructions`, `clarity_pct`
- `past_appointments`, `marked_appointments`, `marking_pct`
- `weekly_health_score`, `weekly_health_status`

**Loop Closure Formula:** Uses same accountable tasks formula: `completed / (completed + overdue)`

**Use Case:** Shows improvement over time - "Your adoption improved from 42 (Critical) to 76 (Good)"

---

### Compounding Proof Views

#### v_compounding_metrics
**Purpose:** Monthly compounding analysis (tasks per lead over time).

---

#### v_aged_lead_conversions ⭐ (NEW Dec 30, 2025)
**Purpose:** Proves compounding by showing appointments from AGED leads.

**Age Buckets:**
| Column | Description |
|--------|-------------|
| `from_0_7_days` | Appointments from leads <7 days old (hot) |
| `from_8_14_days` | Appointments from leads 8-14 days old (warm) |
| `from_15_30_days` | Appointments from leads 15-30 days old (nurtured) |
| `from_30_plus_days` | Appointments from leads 30+ days old (true compounding) |
| `from_60_plus_days` | Appointments from leads 60+ days old (long-term nurture) |
| `pct_from_nurtured_leads` | % from leads 7+ days old |
| `pct_from_15_plus_days` | % from leads 15+ days old |
| `aged_lead_shows` | Shows from leads 15+ days old |
| `avg_lead_age_at_appt_days` | Average lead age when appointment was booked |

**Use Case:** "33% of appointments came from leads that would have been DEAD at a typical dealership"

---

#### v_pipeline_growth ⭐ (NEW Dec 30, 2025)
**Purpose:** Shows pipeline growing month-over-month (not resetting).

**Columns:**
- `location_id`, `dealership_name`, `month`
- `new_leads_this_month`
- `active_from_this_month`, `converted_from_this_month`, `removed_from_this_month`
- `cumulative_active_pipeline` - Running total of active leads
- `cumulative_total_leads` - Running total of all leads
- `mom_new_lead_change` - Month-over-month change in new leads
- `mom_growth_pct` - Month-over-month growth percentage

**Use Case:** "Your pipeline grew from 234 leads to 1,847 leads - 689% increase"

---

### Summary & Trend Views

#### v_daily_summary
**Purpose:** Daily activity summary by dealership.

**Includes:**
- Tasks created/completed
- Reactivations (follow_ups, appointments, removes)
- Appointments (ai_booked, rep_booked, showed, no_shows)

---

#### v_metrics_monthly ⭐ (NEW Dec 30, 2025)
**Purpose:** Monthly rollup of ALL key metrics for month-over-month comparisons.

**Columns:**
- `location_id`, `month`
- **Leads:** `new_leads`, `leads_responded`, `response_rate`, `avg_speed_seconds`
- **Tasks:** `tasks_created`, `tasks_completed`, `loop_closure_pct`
- **Appointments:** `total_appointments`, `ai_booked`, `rep_booked`, `showed`, `no_shows`, `show_rate`
- **Reactivations:** `total_reactivations`, `follow_up_instructions`, `appointment_instructions`, `remove_instructions`

**Use Case:** Compare December vs November performance across all metrics

---

### CS Portfolio Management Views

#### v_cs_account_health ⭐ MATERIALIZED VIEW (Updated Jan 20, 2026 - v7.0.6)
**Purpose:** Single view for CS managers to assess ALL accounts at a glance. Identifies at-risk accounts, shows trends, and provides actionable coaching recommendations.

**Type:** MATERIALIZED VIEW (pre-computed for performance, requires periodic refresh)

**Key Features:**
- Portfolio-level risk assessment
- Health trend tracking (improving/stable/declining)
- Engagement recency monitoring
- Automated primary issue identification
- **Compounding Rate (North Star metric)**
- Compounding proof metrics

**Refresh Command:**
```sql
REFRESH MATERIALIZED VIEW v_health_score;
REFRESH MATERIALIZED VIEW v_cs_account_health;
```
> **Note:** Must refresh `v_health_score` first as `v_cs_account_health` depends on it.

**⭐ NORTH STAR METRIC:**
| Column | Description |
|--------|-------------|
| `compounding_rate` | **(Tasks L30D + Appointments L30D) / New Leads L30D × 100** - Shows pipeline momentum. ≥100% = ACTIVE (compounding), <100% = INACTIVE |

**Compounding Rate Thresholds:**
| Rate | Status | Visual |
|------|--------|--------|
| < 80% | LOW | 🔴 ○ INACTIVE |
| 80-99% | CLOSE | 🟡 ○ INACTIVE |
| ≥ 100% | ACTIVE | 🟢 ⚡ ACTIVE (pulsing glow) |
| ≥ 150% | EXCELLENT | 🟢 ⚡ ACTIVE (pulsing glow) |

**Important:** Compounding Rate ALWAYS uses last 30 days regardless of any date range selection. It's a "current state" metric.

**Health & Risk Columns:**
| Column | Description |
|--------|-------------|
| `adoption_score` | Current health score (0-100) |
| `health_status` | EXCELLENT / GOOD / FAIR / CRITICAL |
| `health_trend` | IMPROVING / STABLE / DECLINING |
| `loop_closure_change` | Change vs previous 30 days |
| `risk_level` | CRITICAL / AT_RISK / NEEDS_ATTENTION / HEALTHY / EXCELLENT |
| `primary_issue` | Actionable coaching recommendation |

**Component Scores:**
| Column | Description |
|--------|-------------|
| `closed_loop_score` | % of accountable tasks completed |
| `clarity_score` | % of complete instructions |
| `marking_score` | % of past appointments marked |

**Task Health:**
| Column | Description |
|--------|-------------|
| `total_tasks` | All tasks for location |
| `completed_tasks` | Tasks completed |
| `overdue_tasks` | Tasks past due and incomplete |
| `overdue_pct` | % of tasks that are overdue |

**Engagement Recency:**
| Column | Description |
|--------|-------------|
| `days_since_activity` | Days since last task/reactivation/appointment |
| `last_task_created` | Most recent task timestamp |
| `last_reactivation` | Most recent reactivation timestamp |
| `last_appointment_booked` | Most recent appointment timestamp |

**Activity Levels (Last 30 Days):**
| Column | Description |
|--------|-------------|
| `tasks_last_30` | Tasks created in last 30 days |
| `completed_last_30` | Tasks completed in last 30 days |
| `reactivations_last_30` | Reactivations in last 30 days |
| `appointments_last_30` | Appointments booked in last 30 days |

**Pipeline Stats:**
| Column | Description |
|--------|-------------|
| `total_leads` | All leads for location |
| `active_leads` | Currently active leads |
| `new_leads_last_30` | New leads in last 30 days |

**Appointment Outcomes:**
| Column | Description |
|--------|-------------|
| `past_appointments` | Appointments that have occurred |
| `showed` | Appointments where customer showed |
| `no_shows` | No-show appointments |
| `unmarked_appointments` | Past appointments needing outcomes |
| `show_rate` | % showed of (showed + no_show) |

**Compounding Proof:**
| Column | Description |
|--------|-------------|
| `pct_from_aged_leads` | % of appointments from leads 15+ days old |

**Risk Level Logic:**
| Level | Criteria |
|-------|----------|
| `CRITICAL` | adoption < 40 AND overdue > 20 |
| `AT_RISK` | adoption < 40 OR declining >10 pts OR inactive >14 days OR overdue >30 |
| `NEEDS_ATTENTION` | adoption < 60 OR overdue >15 OR unmarked >10 |
| `HEALTHY` | adoption 60-79 |
| `EXCELLENT` | adoption ≥80 |

**Primary Issue Examples:**
- "Low loop closure - 47 OVERDUE tasks need attention"
- "Poor instruction quality - train reps on Context + Action + Timing"
- "Unmarked appointments - 12 past appointments need outcomes recorded"
- "Low show rate (42%) - improve confirmation process"
- "Low compounding rate - pipeline not growing, increase adoption"
- "Account healthy - maintain current performance"

**Use Case:** CS manager opens dashboard → sees 3 CRITICAL, 8 AT_RISK accounts → knows exactly who to call and what to discuss. North Star compounding rate shows 10 accounts ACTIVE, 135 INACTIVE.

---

### Lost Opportunity Analysis Views

#### v_lost_opportunity ⭐ (NEW Dec 31, 2025)
**Purpose:** Estimate appointments lost due to adoption gaps. Powers the "Lost Opportunity Analysis" section in CS Dashboard.

**Key Features:**
- Calculates actual appointment conversion rate per dealership
- Estimates lost appointments from overdue tasks
- Estimates lost appointments from poor/empty instructions
- Tracks pipeline leakage (unmarked appointments + rep removals)

**Columns:**
| Column | Description |
|--------|-------------|
| `location_id` | Dealership identifier |
| `dealership_name` | Dealership name |
| `appt_per_completed_task` | Conversion rate: appointments / completed tasks |
| `total_appointments_booked` | Total appointments (for conversion calc) |
| `completed_tasks_all_time` | Total completed tasks (for conversion calc) |
| `overdue_tasks` | Current overdue task count |
| `est_lost_from_overdue` | overdue_tasks × conversion_rate |
| `empty_instructions` | Instructions with no content |
| `incomplete_instructions` | Instructions with 0-1 components |
| `est_lost_from_poor_instructions` | (empty × rate) + (incomplete × rate × 0.3) |
| `unmarked_appointments` | Past appointments without outcome |
| `rep_removals` | Rep-instructed removes (from reactivations) |
| `total_est_lost_appointments` | Sum of all estimated losses |
| `total_tasks` | All tasks for reference |
| `total_reactivations` | All reactivations for reference |
| `complete_instructions` | Instructions with all 3 components |

**Lost Opportunity Formulas:**
```
est_lost_from_overdue = overdue_tasks × appt_per_completed_task

est_lost_from_poor_instructions = 
    (empty_instructions × appt_per_completed_task) +
    (incomplete_instructions × appt_per_completed_task × 0.3)

total_est_lost_appointments = est_lost_from_overdue + est_lost_from_poor_instructions
```

**Important Notes:**
- Uses actual conversion rate from dealer's own data (defensible)
- Empty instructions assumed 0% conversion potential
- Incomplete instructions assumed 30% reduced effectiveness
- Does NOT include unworked no-shows (system auto-recovers these)

**Use Case:** "You have 49 overdue tasks. Based on your conversion rate, that's approximately 12 missed appointments."

---

## Functions

### RPC Functions (56 Total)

#### Primary Data Insertion Functions

| Function | Purpose | Called By |
|----------|---------|-----------|
| `insert_lead()` | Insert or update lead record | Lead Tracker workflow |
| `upsert_task()` | Insert or update task (by task_id) | Drive AI 7.0 workflow |
| `insert_reactivation()` | Insert reactivation and complete tasks | Reactivate Drive workflow |
| `insert_appointment()` | Insert new appointment | Drive AI 7.0 / Reactivate workflow |
| `insert_ai_decision()` | Log AI decision | Drive AI 7.0 workflow |
| `update_appointment_outcome()` | Update outcome status | GHL Appointment Outcome webhook |

#### Lead Update Functions

| Function | Purpose |
|----------|---------|
| `update_first_outbound()` | Set first_outbound_at, triggers speed calculation |
| `update_first_response()` | Set first_response_at, mark responded |
| `update_lead_status()` | Change status (active/converted/removed) |
| `update_lead_source()` | Normalize lead source via dictionary |

#### Bulk Operations

| Function | Purpose |
|----------|---------|
| `bulk_complete_tasks()` | Complete multiple tasks with one reactivation |
| `backfill_speed_to_lead()` | Recalculate speed for historical leads |
| `normalize_all_sources()` | Apply dictionary to all leads |

#### Utility Functions

| Function | Purpose |
|----------|---------|
| `get_dealership_stats()` | Quick stats for a location |
| `get_rep_performance()` | Rep metrics |
| `calculate_health_score()` | Calculate adoption score |

---

## Triggers

### Active Triggers (6)

#### 1. `trg_leads_calculate_speed`
**Table:** `leads`  
**Event:** INSERT or UPDATE of `first_outbound_at`  
**Purpose:** Auto-calculates `speed_to_lead_seconds` when first outbound is recorded

**Logic:**
```sql
-- Only for new_inbound leads with valid first_outbound_at
IF NEW.lead_type = 'new_inbound' 
   AND NEW.first_outbound_at IS NOT NULL 
   AND NEW.lead_date IS NOT NULL 
THEN
    -- Exclude walk-ins, phone-ups
    IF NEW.lead_source_normalized NOT IN ('Walk-In', 'Phone-Up') THEN
        NEW.speed_to_lead_seconds := 
            EXTRACT(EPOCH FROM (NEW.first_outbound_at - NEW.lead_date))::integer;
    END IF;
END IF;
```

---

#### 2. `trg_leads_updated_at`
**Table:** `leads`  
**Event:** UPDATE  
**Purpose:** Auto-updates `updated_at` timestamp

---

#### 3. `trg_tasks_updated_at`
**Table:** `tasks`  
**Event:** UPDATE  
**Purpose:** Auto-updates `updated_at` timestamp

---

#### 4. `trg_reactivations_updated_at`
**Table:** `reactivations`  
**Event:** UPDATE  
**Purpose:** Auto-updates `updated_at` timestamp

---

#### 5. `trg_appointments_updated_at`
**Table:** `appointments`  
**Event:** UPDATE  
**Purpose:** Auto-updates `updated_at` timestamp

---

#### 6. `trg_leads_normalize_source`
**Table:** `leads`  
**Event:** INSERT or UPDATE of `lead_source`  
**Purpose:** Auto-normalizes source using dictionary lookup

---

## Indexes

### Complete Index Inventory (67)

#### leads Table (11 indexes)
```sql
CREATE UNIQUE INDEX idx_leads_contact_id ON leads(contact_id);
CREATE INDEX idx_leads_location_id ON leads(location_id);
CREATE INDEX idx_leads_lead_date ON leads(lead_date);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_leads_lead_type ON leads(lead_type);
CREATE INDEX idx_leads_responded ON leads(responded);
CREATE INDEX idx_leads_appointment_booked ON leads(appointment_booked);
CREATE INDEX idx_leads_speed_to_lead ON leads(speed_to_lead_seconds) WHERE speed_to_lead_seconds IS NOT NULL;
CREATE INDEX idx_leads_location_lead_date ON leads(location_id, lead_date);
CREATE INDEX idx_leads_source_normalized ON leads(lead_source_normalized);
CREATE INDEX idx_leads_created_at ON leads(created_at);
```

#### tasks Table (10 indexes)
```sql
CREATE UNIQUE INDEX idx_tasks_task_id ON tasks(task_id);
CREATE INDEX idx_tasks_location_id ON tasks(location_id);
CREATE INDEX idx_tasks_contact_id ON tasks(contact_id);
CREATE INDEX idx_tasks_completed ON tasks(completed);
CREATE INDEX idx_tasks_assigned_rep_id ON tasks(assigned_rep_id);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_created_at ON tasks(created_at);
CREATE INDEX idx_tasks_location_completed ON tasks(location_id, completed);
CREATE INDEX idx_tasks_location_rep ON tasks(location_id, assigned_rep_id);
CREATE INDEX idx_tasks_completed_by_reactivation ON tasks(completed_by_reactivation_id);
```

#### reactivations Table (7 indexes)
```sql
CREATE INDEX idx_reactivations_location_id ON reactivations(location_id);
CREATE INDEX idx_reactivations_contact_id ON reactivations(contact_id);
CREATE INDEX idx_reactivations_assigned_rep_id ON reactivations(assigned_rep_id);
CREATE INDEX idx_reactivations_action ON reactivations(action);
CREATE INDEX idx_reactivations_reactivated_at ON reactivations(reactivated_at);
CREATE INDEX idx_reactivations_location_rep ON reactivations(location_id, assigned_rep_id);
CREATE INDEX idx_reactivations_location_action ON reactivations(location_id, action);
```

#### appointments Table (9 indexes)
```sql
CREATE INDEX idx_appointments_ghl_id ON appointments(ghl_appointment_id);
CREATE INDEX idx_appointments_location_id ON appointments(location_id);
CREATE INDEX idx_appointments_contact_id ON appointments(contact_id);
CREATE INDEX idx_appointments_appointment_time ON appointments(appointment_time);
CREATE INDEX idx_appointments_outcome_status ON appointments(outcome_status);
CREATE INDEX idx_appointments_created_source ON appointments(created_source);
CREATE INDEX idx_appointments_assigned_rep_id ON appointments(assigned_rep_id);
CREATE INDEX idx_appointments_location_time ON appointments(location_id, appointment_time);
CREATE INDEX idx_appointments_location_outcome ON appointments(location_id, outcome_status);
```

#### ai_decisions Table (5 indexes)
```sql
CREATE INDEX idx_ai_decisions_location_id ON ai_decisions(location_id);
CREATE INDEX idx_ai_decisions_contact_id ON ai_decisions(contact_id);
CREATE INDEX idx_ai_decisions_action ON ai_decisions(action);
CREATE INDEX idx_ai_decisions_decided_at ON ai_decisions(decided_at);
CREATE INDEX idx_ai_decisions_location_action ON ai_decisions(location_id, action);
```

#### task_completions Table (3 indexes)
```sql
CREATE INDEX idx_task_completions_task_id ON task_completions(task_id);
CREATE INDEX idx_task_completions_reactivation_id ON task_completions(reactivation_id);
CREATE INDEX idx_task_completions_completed_at ON task_completions(completed_at);
```

---

## Key Formulas & Business Logic

### Adoption Score (Health Score)

```
Adoption Score = (Loop Closure × 0.40) + (Instruction Quality × 0.30) + (Appointment Marking × 0.30)
```

| Component | Formula | Weight |
|-----------|---------|--------|
| Loop Closure | `completed_tasks / (completed_tasks + overdue_tasks) × 100` | 40% |
| Instruction Quality | `complete_instructions / non_empty_instructions × 100` | 30% |
| Appointment Marking | `marked_past_appointments / total_past_appointments × 100` | 30% |

### ⭐ Compounding Rate (North Star Metric)

```
Compounding Rate = (tasks_last_30 + appointments_last_30) / new_leads_last_30 × 100
```

**Why "Compounding Rate":**
- Measures pipeline momentum - is the pipeline GROWING or SHRINKING?
- Above 100% = Creating more follow-up actions than new leads coming in = COMPOUNDING
- Below 100% = Not nurturing existing leads = pipeline shrinking
- **Single biggest factor for dealership growth using Drive AI**

**Thresholds:**
| Rate | Status | Visual | Meaning |
|------|--------|--------|---------|
| < 80% | LOW | 🔴 ○ INACTIVE | Losing ground - not enough follow-up |
| 80-99% | CLOSE | 🟡 ○ INACTIVE | Almost there - slight improvements needed |
| 100% | THRESHOLD | ─ | Breaking even - pipeline stable |
| 101-149% | GOOD | 🟢 ⚡ ACTIVE | Growing pipeline - compounding unlocked |
| 150%+ | EXCELLENT | 🟢 ⚡ ACTIVE | Strong compounding - significant advantage |

**The Advantage:**
- 100% = Working like a perfect manual sales team (one action per new lead)
- 145% = 45% efficiency advantage over best manual process
- This growth is ONLY possible with AI-powered nurturing

**Important:** Always uses **last 30 days** regardless of date range selection.

### Loop Closure Formula (Updated Dec 31, 2025)

```
closed_loop_pct = completed_tasks / (completed_tasks + overdue_tasks) × 100
```

**Why "Accountable Tasks":**
- Only counts tasks that are **completed** OR **past due**
- Tasks not yet due don't penalize the score
- More fair to dealers with recent task creation
- More actionable: "You have X OVERDUE tasks to close"

**Where:**
- `completed_tasks` = tasks WHERE completed = true
- `overdue_tasks` = tasks WHERE completed = false AND due_date < NOW()

### Health Status Thresholds

| Score | Status | Meaning |
|-------|--------|---------|
| 80+ | EXCELLENT | System fully adopted, focus on optimization |
| 60-79 | GOOD | Minor adoption gaps, quick wins available |
| 40-59 | FAIR | Significant adoption issues, needs attention |
| <40 | CRITICAL | Major problems, intervention required |

### Rep Performance Status

| Status | Criteria |
|--------|----------|
| EXCELLENT | ≥85% loop closure AND ≥70% clarity |
| GOOD | ≥70% loop closure AND ≥50% clarity |
| FAIR | ≥50% loop closure |
| NEEDS_COACHING | <50% loop closure |

### Show Rate

```
Show Rate = showed / (showed + no_show) × 100
```
**Note:** Excludes `cancelled` and `pending` appointments

### Speed-to-Lead

```
Speed (seconds) = first_outbound_at - lead_date
```

**Exclusions:**
- Walk-ins (already at dealership)
- Phone-ups (already talking)
- After-hours leads (8pm-8am local time)

### Instruction Clarity

| Level | Criteria |
|-------|----------|
| Complete | Has Context + Action + Timing |
| Partial | Has 2 of 3 components |
| Incomplete | Has 0-1 components |
| Empty | No instruction text |

### AI vs Rep Removes

| Type | Table | Column |
|------|-------|--------|
| AI Remove | `ai_decisions` | `action = 'remove'` |
| Rep Remove | `reactivations` | `action = 'remove'` |

**They are stored in different tables!**

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              DATA FLOW DIAGRAM                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────────┐                                                           │
│  │   GHL WEBHOOKS   │                                                           │
│  └────────┬─────────┘                                                           │
│           │                                                                      │
│           ▼                                                                      │
│  ┌──────────────────┐     ┌──────────────────┐                                 │
│  │   n8n WORKFLOWS  │────▶│ Supabase RPC     │                                 │
│  │                  │     │ Functions        │                                 │
│  │ • Lead Tracker   │     │                  │                                 │
│  │ • Drive AI 7.0   │     │ • insert_lead()  │                                 │
│  │ • Reactivate     │     │ • upsert_task()  │                                 │
│  │ • Appt Outcome   │     │ • insert_react() │                                 │
│  └──────────────────┘     │ • insert_appt()  │                                 │
│                           └────────┬─────────┘                                 │
│                                    │                                            │
│                                    ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         SUPABASE TABLES                                  │  │
│  │                                                                          │  │
│  │   leads ◄──► tasks ◄──► reactivations ◄──► appointments                │  │
│  │     │                        │                    │                      │  │
│  │     │    ┌───────────────────┤                    │                      │  │
│  │     ▼    ▼                   ▼                    ▼                      │  │
│  │ ai_decisions          task_completions      (outcome updates)            │  │
│  │                                                                          │  │
│  │  [6 TRIGGERS auto-update timestamps, calculate speed, normalize sources]│  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                            │
│                                    ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                          SUPABASE VIEWS (33)                             │  │
│  │                                                                          │  │
│  │  • v_health_score           • v_rep_complete_scorecard                  │  │
│  │  • v_health_trend           • v_instruction_clarity                     │  │
│  │  • v_funnel_metrics         • v_loop_closure_stats                      │  │
│  │  • v_aged_lead_conversions  • v_pipeline_growth                         │  │
│  │  • v_metrics_monthly        • v_appointment_stats                       │  │
│  │  • ... and 23 more                                                       │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                            │
│                                    ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                          HTML DASHBOARDS                                 │  │
│  │                                                                          │  │
│  │  • Drive AI Dashboard (v5)     - Pipeline metrics, appointments        │  │
│  │  • Accountability Dashboard    - Team adoption, rep performance        │  │
│  │                                                                          │  │
│  │  Dashboards query views via Supabase REST API                           │  │
│  │  Headers: apikey: [key], Content-Type: application/json                 │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Relationships

### Primary Keys & Foreign Keys

```
leads.contact_id (UNIQUE)
    ├── tasks.contact_id
    ├── reactivations.contact_id
    ├── appointments.contact_id
    └── ai_decisions.contact_id

tasks.id (PK)
    └── task_completions.task_id (FK)

reactivations.id (PK)
    ├── task_completions.reactivation_id (FK)
    ├── tasks.completed_by_reactivation_id (FK)
    ├── appointments.reactivation_id (FK)
    └── appointments.recovery_reactivation_id (FK)

ai_decisions.id (PK)
    └── tasks.ai_decision_id (FK)
```

### Contact ID is the Universal Linker

All tables connect through `contact_id` which maps to GHL's contact identifier. This allows joining any data about a specific lead across all tables.

```sql
-- Example: Get complete lead journey
SELECT 
    l.lead_name,
    l.lead_date,
    l.speed_to_lead_seconds,
    COUNT(DISTINCT t.id) as task_count,
    COUNT(DISTINCT r.id) as reactivation_count,
    COUNT(DISTINCT a.id) as appointment_count
FROM leads l
LEFT JOIN tasks t ON l.contact_id = t.contact_id
LEFT JOIN reactivations r ON l.contact_id = r.contact_id
LEFT JOIN appointments a ON l.contact_id = a.contact_id
WHERE l.location_id = 'YOUR_LOCATION_ID'
GROUP BY l.id;
```

---

## Quick Reference

### Important Views to Query

| View | Use For |
|------|---------|
| `v_dealerships` | Populate dealership dropdown |
| `v_reps` | Populate rep dropdown |
| `v_health_score` | Adoption score and components |
| `v_health_trend` | Health score over time |
| `v_rep_complete_scorecard` | Rep leaderboard |
| `v_instruction_clarity` | Individual instruction scoring |
| `v_funnel_metrics` | Pipeline performance |
| `v_aged_lead_conversions` | Prove compounding value |
| `v_pipeline_growth` | Show pipeline not resetting |
| `v_metrics_monthly` | Month-over-month comparison |
| `v_cs_account_health` | **CS portfolio management - all accounts at a glance** |
| `v_pipeline_funnel` | **Lead-to-show conversion funnel with opt-outs** |
| `v_rep_appointment_breakdown` | **Per-rep appointment marking and show rates** |
| `v_lost_opportunity` | **Estimate lost appointments from adoption gaps** |

### Materialized View Maintenance

The following views are **MATERIALIZED VIEWS** that must be refreshed to show current data:

| View | Depends On | Refresh Order |
|------|------------|---------------|
| `v_health_score` | Base tables | 1st |
| `v_cs_account_health` | `v_health_score` | 2nd |

**Manual Refresh:**
```sql
REFRESH MATERIALIZED VIEW v_health_score;
REFRESH MATERIALIZED VIEW v_cs_account_health;
```

**Automated Refresh (recommended):**
```sql
-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule hourly refresh
SELECT cron.schedule('refresh-health-views', '0 * * * *', $$
  REFRESH MATERIALIZED VIEW v_health_score;
  REFRESH MATERIALIZED VIEW v_cs_account_health;
$$);
```

> **Why Materialized?** The health score calculations involve multiple table scans and aggregations. Regular views were timing out (>30s). Materialized views pre-compute and cache the results for instant queries (<100ms).

---

### Critical Business Rules

1. **Tasks can ONLY be completed via reactivation** - No other way to close a task
2. **One reactivation can complete multiple tasks** - Bulk completion is possible
3. **AI removes ≠ Rep removes** - Different tables (`ai_decisions` vs `reactivations`)
4. **Speed excludes walk-ins/phone-ups** - Already at dealership or talking
5. **Show rate excludes cancelled/pending** - Only showed/(showed + no_show)
6. **Loop closure uses "accountable" tasks** - Only completed + overdue tasks count
7. **Unmarked appointments = past + pending** - Future appointments don't count as unmarked
8. **Opt-outs from ai_decisions** - `action = 'remove'` in ai_decisions table
9. **Rep removes from reactivations** - `action = 'remove'` in reactivations table

---

## Changelog

### v7.0.6 (January 20, 2026)
- **CRITICAL FIX:** `clarity_score` was not properly aggregating from `v_instruction_clarity`
  - Before fix: avg clarity_score ~6.8% (incorrect)
  - After fix: avg clarity_score ~58-71% (correct)
- **Converted to MATERIALIZED VIEWS:** `v_health_score` and `v_cs_account_health` are now materialized views for performance
  - Regular views were timing out on dashboard queries
  - Materialized views pre-compute data for instant queries
- **Added Indexes:** `idx_health_score_location` and `idx_cs_account_health_location` for fast lookups
- **Refresh Required:** Views must be refreshed periodically to show current data:
  ```sql
  REFRESH MATERIALIZED VIEW v_health_score;
  REFRESH MATERIALIZED VIEW v_cs_account_health;
  ```
- **Recommended:** Set up hourly cron job to auto-refresh views
- **35 views + 2 materialized views** - CS Dashboard performance optimized

### v7.0.5 (December 31, 2025)
- **Added Column:** `compounding_rate` to `v_cs_account_health` - **NORTH STAR METRIC**
- **Formula:** `(tasks_last_30 + appointments_last_30) / new_leads_last_30 × 100`
- **Purpose:** Shows pipeline momentum. ≥100% = ACTIVE (compounding), <100% = INACTIVE
- **Always L30D:** Compounding Rate always uses last 30 days regardless of date selection
- **Updated Primary Issues:** Added "Low compounding rate" as detectable issue
- **37 views total** - CS Dashboard ready with North Star metric

### v7.0.4 (December 31, 2025)
- **Added View:** `v_pipeline_funnel` - Complete lead-to-show funnel with proper opt-out tracking from ai_decisions
- **Added View:** `v_rep_appointment_breakdown` - Per-rep appointment marking rates and show rates
- **Added View:** `v_lost_opportunity` - Estimate lost appointments from overdue tasks and poor instructions
- **Fixed:** `v_pipeline_funnel` uses actual appointments join instead of unreliable `appointment_booked` flag
- **Fixed:** Opt-outs now correctly sourced from `ai_decisions.action = 'remove'`
- **37 views total** - CS Dashboard ready

### v7.0.3 (December 31, 2025)
- **Added View:** `v_cs_account_health` - CS portfolio management view with risk assessment, trends, and coaching recommendations
- **34 views total** - Complete analytics architecture

### v7.0.2 (December 31, 2025)
- **Updated Loop Closure Formula:** Changed from `completed/total` to `completed/(completed+overdue)` for fairer scoring
- **Updated Views:** `v_loop_closure_stats`, `v_health_score`, `v_health_trend`, `v_rep_complete_scorecard`
- **Added Columns:** `overdue_tasks` to health views, `pending_not_due` to loop closure stats
- **Clarified:** Unmarked appointments only count past appointments

### v7.0.1 (December 30, 2025)
- **Added Views:** `v_aged_lead_conversions`, `v_pipeline_growth`, `v_health_trend`, `v_metrics_monthly`
- **Updated:** `v_instruction_clarity` with expanded regex patterns (49% complete rate)
- **Added:** `health_status` column to `v_health_score`
- **Added:** Speed-to-lead trigger `trg_leads_calculate_speed`
- **Verified:** Complete data integrity audit (24/24 checks passing)

---

*Document last updated: January 20, 2026*
*Verified: 7 Tables | 35 Views | 2 Materialized Views | 56 Functions | 6 Triggers | 69 Indexes*
