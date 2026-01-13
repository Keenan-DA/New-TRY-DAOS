# DA-OS Quick Reference

## Raw Data (What Comes In)

### From GHL

| Field | Table | Description |
|-------|-------|-------------|
| `contact_id` | leads | Unique GHL contact ID |
| `location_id` | leads | Dealership location ID |
| `lead_name` | leads | Full name |
| `lead_phone` | leads | Phone number |
| `lead_email` | leads | Email address |
| `lead_source` | leads | Raw source string (e.g., "Facebook - 2024 Silverado") |
| `lead_date` | leads | When contact was created in GHL |
| `first_outbound_at` | leads | First message sent timestamp |
| `first_response_at` | leads | First reply received timestamp |
| `ghl_appointment_id` | appointments | Unique GHL appointment ID |
| `appointment_time` | appointments | Scheduled date/time |
| `appointment_status` | appointments | GHL status (confirmed, etc.) |
| `outcome_status` | appointments | showed, no_show, cancelled, pending |

### From n8n Workflows

| Field | Table | Source Workflow |
|-------|-------|-----------------|
| `task_id` | tasks | Drive AI 7.0 |
| `task_description` | tasks | Drive AI 7.0 |
| `due_date` | tasks | Drive AI 7.0 |
| `action` | ai_decisions | Drive AI 7.0 (task/appointment/remove/follow_up) |
| `confidence` | ai_decisions | Drive AI 7.0 (0.0-1.0) |
| `instruction` | reactivations | Reactivate Drive |
| `created_source` | appointments | Both workflows + webhook |

---

## Calculated Data (What We Generate)

### Lead Metrics

| Field | Formula | Nuances |
|-------|---------|---------|
| `lead_source_normalized` | Dictionary lookup on `lead_source` | Standardizes "FB - Silverado" → "Facebook" |
| `lead_source_category` | From dictionary | Groups sources: Paid, Organic, Referral, etc. |
| `speed_to_lead_seconds` | `first_outbound_at - lead_date` | **EXCLUDES:** Walk-In, Phone-Up, aged uploads |
| `time_to_response_minutes` | `(first_response_at - first_outbound_at) / 60` | Only if customer responded |
| `responded` | `true` if `first_response_at` exists | Boolean flag |

### Speed to Lead

```sql
speed_to_lead_seconds = EXTRACT(EPOCH FROM (first_outbound_at - lead_date))
```

**IMPORTANT EXCLUSIONS:**
| Excluded | Reason |
|----------|--------|
| Walk-In | Customer already at dealership |
| Phone-Up | Real-time phone call |
| Aged Upload | `lead_type = 'aged_upload'` - not new leads |
| Service | `lead_type = 'service'` - different workflow |

**ONLY INCLUDED:**
- `lead_type = 'new_inbound'`
- `lead_source_normalized NOT IN ('Walk-In', 'Phone-Up')`
- Internet/digital leads only

---

### Task Metrics

| Metric | Formula | Nuances |
|--------|---------|---------|
| `completed_tasks` | `COUNT(*) WHERE completed = true` | Tasks marked done via Reactivate Drive |
| `overdue_tasks` | `COUNT(*) WHERE completed = false AND due_date < NOW()` | Past due, not completed |
| `pending_tasks` | `COUNT(*) WHERE completed = false AND due_date >= NOW()` | Not yet due |
| `closed_loop_pct` | `completed / (completed + overdue) × 100` | **Excludes pending** - fair to new accounts |

**Closed Loop % Nuance:**
```
Denominator = completed + overdue (NOT total tasks)

Example:
  - 50 completed
  - 10 overdue
  - 40 pending (not yet due)

  closed_loop_pct = 50 / (50 + 10) = 83.3%

  ✓ Pending tasks don't penalize the score
  ✓ Only tasks that SHOULD be done are counted
```

---

### Appointment Metrics

| Metric | Formula | Nuances |
|--------|---------|---------|
| `ai_booked` | `COUNT(*) WHERE created_source = 'ai_automated'` | Drive AI 7.0 bookings |
| `rep_instructed` | `COUNT(*) WHERE created_source = 'rep_instructed'` | Via Reactivate Drive form |
| `rep_manual` | `COUNT(*) WHERE created_source = 'rep_manual'` | Direct GHL calendar booking |
| `human_booked` | `rep_instructed + rep_manual` | All human-initiated |
| `show_rate` | `showed / (showed + no_show) × 100` | **Excludes cancelled & pending** |
| `marking_pct` | `marked / past_appointments × 100` | % of past appts with outcome recorded |

**Show Rate Nuance:**
```sql
show_rate = showed / (showed + no_show) × 100

-- EXCLUDES from denominator:
-- - cancelled (customer cancelled, not a no-show)
-- - pending (hasn't happened yet)

-- ONLY counts appointments that:
-- 1. Already occurred (appointment_time < NOW())
-- 2. Have definitive outcome (showed OR no_show)
```

**AI/Human Ratio:**
```sql
ai_human_ratio = ai_booked / human_booked

-- Balance Status:
CASE
  WHEN ratio < 0.5 THEN 'AI_UNDERUTILIZED'      -- AI booking less than half of humans
  WHEN ratio BETWEEN 0.8 AND 1.2 THEN 'BALANCED' -- Roughly equal
  WHEN ratio > 2.0 THEN 'STAFF_UNDERPERFORMING'  -- AI doing 2x+ more than humans
END
```

---

### Instruction Clarity (Reactivate Drive)

| Level | Criteria | Example |
|-------|----------|---------|
| `complete` | Has context + action + timing | "Call John about his 2024 Silverado trade-in tomorrow at 10am" |
| `good` | Has context + action | "Follow up on the F-150 inquiry" |
| `basic` | Has action only | "Call them" |
| `incomplete` | Missing action | "Customer interested" |

**Detection Patterns:**
```sql
has_context = instruction matches vehicle/customer/situation patterns
has_action = instruction matches call/text/email/follow-up patterns
has_timing = instruction matches today/tomorrow/time/date patterns

-- Vehicle patterns include 50+ makes:
'silverado|f-150|camry|accord|civic|mustang|...'
```

**Clarity Score:**
```sql
clarity_score = complete_instructions / non_empty_instructions × 100

-- EXCLUDES empty instructions (no text at all)
```

---

### Health Score (Adoption)

```sql
adoption_score =
  (closed_loop_score × 0.40) +
  (clarity_score × 0.30) +
  (marking_score × 0.30)
```

| Component | Weight | What It Measures |
|-----------|--------|------------------|
| `closed_loop_score` | 40% | Task completion discipline |
| `clarity_score` | 30% | Instruction quality |
| `marking_score` | 30% | Appointment outcome tracking |

**Health Status:**
| Score | Status | Action |
|-------|--------|--------|
| 80-100 | `HEALTHY` | Maintain |
| 60-79 | `AT_RISK` | Monitor closely |
| 40-59 | `NEEDS_ATTENTION` | Intervene |
| 0-39 | `CRITICAL` | Urgent action |

---

### Pipeline Funnel

```
Total Leads
    ↓ contact_rate
Contacted (first_outbound_at exists)
    ↓ response_rate
Responded (responded = true)
    ↓ appointment_rate
Appointed (has appointment)
    ↓ show_rate
Showed (outcome_status = 'showed')
```

**Conversion Rates:**
```sql
contact_rate = contacted / total_leads × 100
response_rate = responded / contacted × 100
appointment_rate = appointed / responded × 100
show_rate = showed / appointed × 100
```

---

### Compounding Rate (North Star)

```sql
compounding_rate = (tasks_last_30 + appointments_last_30) / new_leads_last_30 × 100
```

**What It Measures:**
- How much "activity" is generated per new lead
- Higher = more nurture effort per lead
- Target: 100%+ (at least 1 task or appointment per lead)

**Nuance:**
- Counts ALL tasks and appointments (AI + human)
- May double-count if appointment resulted from task
- Division by zero if no new leads (returns NULL)

---

## Key Exclusions Summary

| Metric | What's EXCLUDED | Why |
|--------|-----------------|-----|
| Speed to Lead | Walk-In, Phone-Up | Already engaged in real-time |
| Speed to Lead | Aged uploads | Not new leads |
| Speed to Lead | Service leads | Different workflow |
| Closed Loop % | Pending tasks | Not yet due |
| Show Rate | Cancelled appts | Customer decision, not no-show |
| Show Rate | Pending appts | Haven't occurred yet |
| Clarity Score | Empty instructions | No text to analyze |

---

## Date Range Conventions

| View | Default Range | Configurable |
|------|---------------|--------------|
| `v_speed_to_lead` | Last 30 days | Via WHERE clause |
| `v_loop_closure_stats` | All time | Via WHERE clause |
| `v_appointment_stats` | All time | Via WHERE clause |
| `v_cs_account_health` | Last 30 days | Hardcoded |
| `v_compounding_rate` | Last 30 days | Hardcoded |

---

## Quick SQL Snippets

### Check Speed to Lead (with exclusions)
```sql
SELECT
    location_id,
    AVG(speed_to_lead_seconds) as avg_speed,
    COUNT(*) as lead_count
FROM leads
WHERE lead_type = 'new_inbound'
  AND lead_source_normalized NOT IN ('Walk-In', 'Phone-Up')
  AND speed_to_lead_seconds IS NOT NULL
  AND created_at > NOW() - INTERVAL '30 days'
GROUP BY location_id;
```

### Check Appointment Attribution
```sql
SELECT
    created_source,
    COUNT(*) as count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 1) as pct
FROM appointments
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY created_source;
```

### Check Show Rate (proper exclusions)
```sql
SELECT
    location_id,
    COUNT(*) FILTER (WHERE outcome_status = 'showed') as showed,
    COUNT(*) FILTER (WHERE outcome_status = 'no_show') as no_show,
    ROUND(
        COUNT(*) FILTER (WHERE outcome_status = 'showed')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE outcome_status IN ('showed', 'no_show')), 0) * 100
    , 1) as show_rate
FROM appointments
WHERE appointment_time < NOW()  -- Only past appointments
GROUP BY location_id;
```

### Check Loop Closure (with pending excluded)
```sql
SELECT
    location_id,
    COUNT(*) FILTER (WHERE completed = true) as completed,
    COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) as overdue,
    COUNT(*) FILTER (WHERE completed = false AND due_date >= NOW()) as pending,
    ROUND(
        COUNT(*) FILTER (WHERE completed = true)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE completed = true OR (completed = false AND due_date < NOW())), 0) * 100
    , 1) as closed_loop_pct
FROM tasks
GROUP BY location_id;
```
