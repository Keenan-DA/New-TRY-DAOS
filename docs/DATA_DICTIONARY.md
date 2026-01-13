# DA-OS Data Dictionary

## Overview

This document defines ALL data fields in the system:
- **RAW DATA** = Directly from GHL/n8n (stored as-is)
- **CALCULATED DATA** = Derived via triggers, views, or RPC functions

---

## 1. LEADS TABLE

### Raw Data (from GHL)

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `contact_id` | TEXT | GHL | Unique GHL contact identifier |
| `location_id` | TEXT | GHL | Dealership location ID |
| `lead_name` | TEXT | GHL | Full name |
| `lead_first_name` | TEXT | GHL | First name |
| `lead_last_name` | TEXT | GHL | Last name |
| `lead_phone` | TEXT | GHL | Phone number |
| `lead_email` | TEXT | GHL | Email address |
| `lead_source` | TEXT | GHL | Raw source string (e.g., "Facebook - 2024 Silverado") |
| `lead_date` | TIMESTAMPTZ | GHL | When lead was created in GHL |
| `original_lead_date` | TIMESTAMPTZ | GHL | Original date for aged uploads |
| `lead_type` | TEXT | GHL/n8n | Classification: `new_inbound`, `aged_upload`, `rep_created` |

### Calculated Data

| Field | Type | Calculation | Formula/Logic |
|-------|------|-------------|---------------|
| `lead_source_normalized` | TEXT | Trigger | Dictionary lookup: `lead_source_dictionary.normalized_name` WHERE pattern matches |
| `lead_source_category` | TEXT | Trigger | From dictionary: `category` column |
| `speed_to_lead_seconds` | INTEGER | Trigger | `EXTRACT(EPOCH FROM (first_outbound_at - lead_date))` |
| `time_to_outbound_minutes` | INTEGER | Derived | `speed_to_lead_seconds / 60` |
| `time_to_response_minutes` | INTEGER | Derived | `EXTRACT(EPOCH FROM (first_response_at - first_outbound_at)) / 60` |
| `responded` | BOOLEAN | RPC | Set to `true` when first_response_at is populated |
| `status` | TEXT | RPC | `active` → `converted` (if appointment showed) or `removed` |

### Speed Calculation Exclusions

```sql
-- Trigger: trg_leads_calculate_speed
-- EXCLUDES from speed calculation:
WHERE lead_type = 'new_inbound'              -- Only new leads
  AND lead_source_normalized NOT IN ('Walk-In', 'Phone-Up')  -- Exclude walk-ins
  AND first_outbound_at IS NOT NULL          -- Must have outbound
  AND lead_date IS NOT NULL                  -- Must have lead date
```

---

## 2. TASKS TABLE

### Raw Data (from n8n/Drive AI 7.0)

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `task_id` | TEXT | n8n | Unique task ID (trace_id from n8n) |
| `contact_id` | TEXT | n8n | Link to lead |
| `location_id` | TEXT | n8n | Dealership |
| `task_description` | TEXT | AI | AI-generated task description |
| `due_date` | TIMESTAMPTZ | AI | When task should be completed |
| `priority` | TEXT | AI | `high`, `medium`, `low` |
| `ai_decision_id` | UUID | n8n | Link to AI decision that created it |

### Calculated Data (in views)

| Metric | View | Formula |
|--------|------|---------|
| `is_overdue` | v_tasks_detail | `completed = false AND due_date < NOW()` |
| `hours_to_complete` | v_task_efficiency | `EXTRACT(EPOCH FROM (completed_at - created_at)) / 3600` |
| `days_overdue` | v_overdue_tasks | `EXTRACT(DAY FROM (NOW() - due_date))` |

---

## 3. APPOINTMENTS TABLE

### Raw Data

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `ghl_appointment_id` | TEXT | GHL | Unique GHL appointment ID |
| `contact_id` | TEXT | GHL/n8n | Link to lead |
| `location_id` | TEXT | GHL/n8n | Dealership |
| `calendar_id` | TEXT | GHL | Which calendar booked on |
| `appointment_time` | TIMESTAMPTZ | GHL/n8n | Scheduled date/time |
| `appointment_type` | TEXT | GHL/n8n | Sales, Service, Test Drive |
| `assigned_rep_id` | TEXT | GHL | Rep assigned to appointment |
| `assigned_rep_name` | TEXT | GHL | Rep name |
| `status` | TEXT | GHL | GHL's internal status |
| `appointment_status` | TEXT | GHL | confirmed, cancelled, etc. |

### Attribution Data

| Field | Type | Source | Values |
|-------|------|--------|--------|
| `created_source` | TEXT | n8n/webhook | `ai_automated` = Drive AI 7.0 booked |
| | | | `rep_instructed` = Reactivate Drive booked |
| | | | `rep_manual` = Rep booked in GHL calendar |
| `source_workflow` | TEXT | n8n | `drive_ai_7`, `reactivate_drive`, `ghl_calendar` |
| `reactivation_id` | UUID | n8n | Link to reactivation (if rep_instructed) |

### Outcome Data

| Field | Type | Source | Values |
|-------|------|--------|--------|
| `outcome_status` | TEXT | GHL webhook | `pending` = Not yet occurred |
| | | | `showed` = Customer showed up |
| | | | `no_show` = Customer didn't show |
| | | | `cancelled` = Appointment cancelled |
| `outcome_recorded_at` | TIMESTAMPTZ | webhook | When outcome was recorded |
| `outcome_recorded_by` | TEXT | webhook | `ghl_webhook`, `manual`, etc. |

### Calculated Metrics (in views)

| Metric | View | Formula |
|--------|------|---------|
| `show_rate` | v_appointment_stats | `showed / (showed + no_show) × 100` |
| `marking_pct` | v_appointment_stats | `marked / past_appointments × 100` |
| `is_unmarked` | v_unmarked_appointments | `outcome_status = 'pending' AND appointment_time < NOW()` |

---

## 4. REACTIVATIONS TABLE

### Raw Data (from Reactivate Drive form)

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `contact_id` | TEXT | Form | Lead being reactivated |
| `location_id` | TEXT | Form | Dealership |
| `rep_id` | TEXT | Form | Rep who submitted |
| `rep_name` | TEXT | Form | Rep name |
| `action` | TEXT | AI | `follow_up`, `appointment`, `remove` |
| `instruction_raw` | TEXT | Form | Raw instruction from rep |
| `instruction` | TEXT | n8n | Cleaned instruction |
| `reactivated_at` | TIMESTAMPTZ | n8n | When submitted |

### Calculated Data

| Field | Type | Calculation | Formula |
|-------|------|-------------|---------|
| `instruction_length` | INTEGER | n8n | `LENGTH(instruction)` |
| `instruction_word_count` | INTEGER | n8n | `ARRAY_LENGTH(REGEXP_SPLIT_TO_ARRAY(instruction, '\s+'), 1)` |
| `tasks_completed_count` | INTEGER | RPC | Count of tasks marked complete by this reactivation |

---

## 5. AI_DECISIONS TABLE

### Raw Data (from Drive AI 7.0)

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `contact_id` | TEXT | n8n | Lead analyzed |
| `location_id` | TEXT | n8n | Dealership |
| `action` | TEXT | AI | `task`, `appointment`, `follow_up`, `remove` |
| `confidence` | NUMERIC | AI | 0.0 - 1.0 confidence score |
| `reasoning` | TEXT | AI | Why AI made this decision |
| `conversation_length` | INTEGER | n8n | Number of messages analyzed |
| `decided_at` | TIMESTAMPTZ | n8n | When decision was made |

---

## 6. KEY VIEW FORMULAS

### v_loop_closure_stats (Task Completion)

```sql
-- Closed Loop Percentage
closed_loop_pct = completed_tasks / (completed_tasks + overdue_tasks) × 100

WHERE:
  completed_tasks = COUNT(*) FROM tasks WHERE completed = true
  overdue_tasks = COUNT(*) FROM tasks WHERE completed = false AND due_date < NOW()

-- Note: Tasks not yet due are EXCLUDED from denominator (fair to new accounts)
```

### v_appointment_stats (Appointment Metrics)

```sql
-- Show Rate
show_rate = showed / (showed + no_show) × 100
-- Note: Excludes cancelled and pending

-- Marking Percentage
marking_pct = marked_past / total_past × 100

WHERE:
  marked_past = COUNT(*) WHERE outcome_status != 'pending' AND appointment_time < NOW()
  total_past = COUNT(*) WHERE appointment_time < NOW()
```

### v_ai_human_ratio (Booking Attribution)

```sql
-- AI vs Human Booking Ratio
ai_human_ratio = ai_booked / human_booked

WHERE:
  ai_booked = COUNT(*) WHERE created_source = 'ai_automated'
  human_booked = COUNT(*) WHERE created_source IN ('rep_instructed', 'rep_manual')

-- Balance Status
CASE
  WHEN ratio < 0.5 THEN 'AI_UNDERUTILIZED'
  WHEN ratio BETWEEN 0.8 AND 1.2 THEN 'BALANCED'
  WHEN ratio > 2.0 THEN 'STAFF_UNDERPERFORMING'
  ELSE 'OK'
END
```

### v_instruction_clarity (Instruction Quality)

```sql
-- Clarity Level based on regex patterns
clarity_level = CASE
  WHEN has_context AND has_action AND has_timing THEN 'complete'
  WHEN has_context AND has_action THEN 'good'
  WHEN has_action THEN 'basic'
  ELSE 'incomplete'
END

WHERE:
  has_context = instruction ~ (vehicle_pattern OR customer_pattern OR situation_pattern)
  has_action = instruction ~ (call_pattern OR text_pattern OR email_pattern OR follow_up_pattern)
  has_timing = instruction ~ (today_pattern OR tomorrow_pattern OR time_pattern OR date_pattern)
```

### v_health_score (Adoption Score)

```sql
-- Overall Health Score (0-100)
adoption_score =
  (closed_loop_score × 0.40) +
  (clarity_score × 0.30) +
  (marking_score × 0.30)

WHERE:
  closed_loop_score = completed / (completed + overdue) × 100
  clarity_score = complete_instructions / non_empty_instructions × 100
  marking_score = marked_past_appointments / total_past_appointments × 100

-- Health Status
CASE
  WHEN adoption_score >= 80 THEN 'HEALTHY'
  WHEN adoption_score >= 60 THEN 'AT_RISK'
  WHEN adoption_score >= 40 THEN 'NEEDS_ATTENTION'
  ELSE 'CRITICAL'
END
```

### v_speed_to_lead (Response Speed)

```sql
-- Average Speed to Lead (seconds)
avg_speed = AVG(speed_to_lead_seconds)

-- Speed Buckets
speed_bucket = CASE
  WHEN speed_to_lead_seconds <= 60 THEN 'under_1_min'
  WHEN speed_to_lead_seconds <= 300 THEN '1_to_5_min'
  WHEN speed_to_lead_seconds <= 900 THEN '5_to_15_min'
  WHEN speed_to_lead_seconds <= 3600 THEN '15_to_60_min'
  ELSE 'over_1_hour'
END

-- Exclusions: Walk-ins, Phone-ups, Aged uploads
```

### v_pipeline_funnel (Conversion Funnel)

```sql
-- Funnel Stages
total_leads = COUNT(*)
contacted = COUNT(*) WHERE first_outbound_at IS NOT NULL
responded = COUNT(*) WHERE responded = true
appointed = COUNT(*) WHERE appointment_booked = true  -- ⚠️ This flag may be stale
showed = COUNT(*) WHERE has appointment with outcome_status = 'showed'

-- Conversion Rates
contact_rate = contacted / total_leads × 100
response_rate = responded / contacted × 100
appointment_rate = appointed / responded × 100
show_rate = showed / appointed × 100
```

### v_compounding_rate (North Star Metric)

```sql
-- ⚠️ ISSUE: This formula has problems (see issues)
compounding_rate = (tasks_last_30 + appointments_last_30) / new_leads_last_30 × 100

-- PROBLEM 1: Division by zero if new_leads = 0
-- PROBLEM 2: Double-counts (appointments often RESULT from tasks)
-- SUGGESTED FIX:
compounding_rate = (completed_tasks + showed_appointments) / NULLIF(new_leads, 0) × 100
```

### v_lost_opportunity (Missed Appointments)

```sql
-- Estimated lost appointments due to poor adoption
appt_per_completed_task = total_appointments / total_completed_tasks

est_lost_from_overdue = overdue_tasks × appt_per_completed_task
est_lost_from_poor_instructions =
  (empty_instructions × conversion_rate) +
  (incomplete_instructions × conversion_rate × 0.3)

total_est_lost = est_lost_from_overdue + est_lost_from_poor_instructions
```

---

## 7. DATA FLOW SUMMARY

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              RAW DATA IN                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  GHL → Lead Created                                                          │
│    └─► leads (contact_id, name, phone, email, source, date)                 │
│        └─► TRIGGER: normalize source → lead_source_normalized               │
│                                                                              │
│  GHL → Outbound Sent                                                         │
│    └─► leads.first_outbound_at                                              │
│        └─► TRIGGER: calculate speed_to_lead_seconds                         │
│                                                                              │
│  GHL → Response Received                                                     │
│    └─► leads.first_response_at, responded = true                            │
│                                                                              │
│  Drive AI 7.0 → Decision Made                                                │
│    └─► ai_decisions (action, confidence, reasoning)                         │
│    └─► tasks (if action = 'task')                                           │
│    └─► appointments (if action = 'appointment', created_source = ai_auto)   │
│                                                                              │
│  Reactivate Drive → Rep Submits Form                                         │
│    └─► reactivations (action, instruction, rep_id)                          │
│    └─► tasks.completed = true (for matching contact_id)                     │
│    └─► appointments (if action = 'appointment', created_source = rep_instr) │
│                                                                              │
│  GHL → Appointment Created (manual)                                          │
│    └─► appointments (created_source = rep_manual)                           │
│                                                                              │
│  GHL → Appointment Status Changed                                            │
│    └─► appointments.outcome_status (showed/no_show/cancelled)               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CALCULATED DATA OUT                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SPEED METRICS (v_speed_to_lead)                                             │
│    └─► avg_speed_seconds, speed_buckets, median_speed                       │
│                                                                              │
│  TASK METRICS (v_loop_closure_stats)                                         │
│    └─► completed_tasks, overdue_tasks, closed_loop_pct                      │
│                                                                              │
│  APPOINTMENT METRICS (v_appointment_stats)                                   │
│    └─► ai_booked, human_booked, show_rate, marking_pct                      │
│                                                                              │
│  INSTRUCTION METRICS (v_instruction_clarity)                                 │
│    └─► clarity_level (complete/good/basic/incomplete), patterns_found       │
│                                                                              │
│  HEALTH SCORE (v_health_score)                                               │
│    └─► adoption_score (0-100), health_status                                │
│                                                                              │
│  FUNNEL METRICS (v_pipeline_funnel)                                          │
│    └─► contact_rate, response_rate, appointment_rate, show_rate             │
│                                                                              │
│  ATTRIBUTION (v_ai_human_ratio)                                              │
│    └─► ai_booked, rep_instructed, rep_manual, ratio, balance_status         │
│                                                                              │
│  OPPORTUNITY (v_lost_opportunity)                                            │
│    └─► est_lost_appointments, est_lost_revenue                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. TRIGGER REFERENCE

| Trigger | Table | Event | Action |
|---------|-------|-------|--------|
| `trg_leads_calculate_speed` | leads | INSERT/UPDATE first_outbound_at | Calculate speed_to_lead_seconds |
| `trg_leads_normalize_source` | leads | INSERT/UPDATE lead_source | Lookup normalized source from dictionary |
| `trg_leads_updated_at` | leads | UPDATE | Set updated_at = NOW() |
| `trg_tasks_updated_at` | tasks | UPDATE | Set updated_at = NOW() |
| `trg_appointments_updated_at` | appointments | UPDATE | Set updated_at = NOW() |
| `trg_reactivations_updated_at` | reactivations | UPDATE | Set updated_at = NOW() |

---

## 9. RPC FUNCTION REFERENCE

| Function | Purpose | Called By |
|----------|---------|-----------|
| `insert_lead()` | Insert new lead | Lead Tracker workflow |
| `upsert_task()` | Insert/update task by task_id | Drive AI 7.0 |
| `insert_ai_decision()` | Log AI decision | Drive AI 7.0 |
| `insert_appointment()` | Insert appointment (AUTHORITATIVE) | Drive AI 7.0, Reactivate Drive |
| `upsert_appointment_from_webhook()` | Insert appointment (PASSIVE) | GHL webhook |
| `insert_reactivation()` | Insert reactivation + complete tasks | Reactivate Drive |
| `update_appointment_outcome()` | Update outcome status | GHL webhook |
| `update_first_outbound()` | Set first_outbound_at | GHL webhook |
| `update_first_response()` | Set first_response_at | GHL webhook |

---

## 10. INDEX REFERENCE

### Critical Indexes (Exist)

| Table | Index | Columns |
|-------|-------|---------|
| leads | idx_leads_contact_id | contact_id (UNIQUE) |
| leads | idx_leads_location_id | location_id |
| leads | idx_leads_lead_date | lead_date |
| tasks | idx_tasks_contact_id | contact_id |
| tasks | idx_tasks_completed | completed |
| appointments | idx_appointments_ghl_id | ghl_appointment_id (UNIQUE) |
| appointments | idx_appointments_location_id | location_id |
| appointments | idx_appointments_created_source | created_source |

### Missing Indexes (Need to Add)

| Table | Suggested Index | Purpose |
|-------|-----------------|---------|
| lead_source_dictionary | idx_lsd_normalized | Speed up source lookups |
| tasks | idx_tasks_closure | (location_id, completed, due_date) for loop closure |
| appointments | idx_appts_time_outcome | (appointment_time, outcome_status) for unmarked queries |
