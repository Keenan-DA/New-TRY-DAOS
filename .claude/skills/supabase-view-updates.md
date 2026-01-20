# Skill: Supabase View Updates

## Overview
This skill documents the safe procedure for updating Supabase views in the DA-OS project. Views have dependencies and must be updated in the correct order.

## Critical Rules

### 1. NEVER Use CREATE OR REPLACE Alone
PostgreSQL's `CREATE OR REPLACE VIEW` cannot:
- Drop columns from a view
- Change column types
- Handle dependent views

**ALWAYS drop and recreate views when modifying structure.**

### 2. Check Dependencies FIRST
Before modifying any view, run this query to find dependent views:

```sql
SELECT DISTINCT dependent_view.relname AS dependent_view
FROM pg_depend
JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
JOIN pg_class AS dependent_view ON pg_rewrite.ev_class = dependent_view.oid
JOIN pg_class AS source_view ON pg_depend.refobjid = source_view.oid
WHERE source_view.relname = 'VIEW_NAME_HERE';
```

### 3. Get Dependent View Definitions
Before dropping, capture the SQL for dependent views:

```sql
SELECT pg_get_viewdef('view_name_here', true);
```

### 4. Drop Order: Dependents First, Base Last
```sql
DROP VIEW IF EXISTS dependent_view_2;
DROP VIEW IF EXISTS dependent_view_1;
DROP VIEW IF EXISTS base_view;
```

### 5. Create Order: Base First, Dependents Last
```sql
CREATE VIEW base_view AS ...;
CREATE VIEW dependent_view_1 AS ...;
CREATE VIEW dependent_view_2 AS ...;
```

## Known View Dependencies

### v_instruction_clarity Chain
```
v_instruction_clarity (base - uses reactivations table)
    └── v_instruction_log (depends on v_instruction_clarity)
```

**Update Procedure:**
1. Get v_instruction_log definition: `SELECT pg_get_viewdef('v_instruction_log', true);`
2. Drop v_instruction_log
3. Drop v_instruction_clarity
4. Create v_instruction_clarity (new version)
5. Create v_instruction_log (using saved definition)

### Required Columns for v_instruction_clarity
The view MUST include these columns from `reactivations` table for `v_instruction_log` to work:
- id
- location_id
- dealership_name
- contact_id
- lead_name
- assigned_rep_id
- rep_name
- instruction
- action
- follow_up_message
- follow_up_date
- appointment_type
- appointment_time
- reactivated_at
- created_at
- has_context (computed)
- has_action (computed)
- has_timing (computed)
- weighted_score (computed)
- clarity_level (computed)

## Complete Update Template

```sql
-- ============================================================
-- Safe View Update Template
-- ============================================================

-- Step 1: Drop dependent views (reverse dependency order)
DROP VIEW IF EXISTS v_instruction_log;

-- Step 2: Drop base view
DROP VIEW IF EXISTS v_instruction_clarity;

-- Step 3: Create base view with ALL required columns
CREATE OR REPLACE VIEW v_instruction_clarity AS
WITH instruction_analysis AS (
  SELECT
    r.id,
    r.location_id,
    r.dealership_name,
    r.contact_id,
    r.lead_name,
    r.assigned_rep_id,
    r.rep_name,
    r.instruction,
    r.action,
    r.follow_up_message,
    r.follow_up_date,
    r.appointment_type,
    r.appointment_time,
    r.reactivated_at,
    r.created_at,
    -- Add computed columns here
    CASE WHEN ... THEN TRUE ELSE FALSE END AS has_context,
    CASE WHEN ... THEN TRUE ELSE FALSE END AS has_action,
    CASE WHEN ... THEN TRUE ELSE FALSE END AS has_timing
  FROM reactivations r
  WHERE r.action != 'remove' OR r.action IS NULL
)
SELECT
  ia.*,
  (...) AS weighted_score,
  CASE ... END AS clarity_level
FROM instruction_analysis ia;

-- Step 4: Recreate dependent views
CREATE OR REPLACE VIEW v_instruction_log AS
SELECT
  id, location_id, dealership_name, contact_id, lead_name,
  assigned_rep_id, rep_name, instruction, action, clarity_level,
  has_context, has_action, has_timing, follow_up_message,
  follow_up_date, appointment_type, appointment_time, reactivated_at,
  CASE action
    WHEN 'follow_up' THEN 'Follow-up'
    WHEN 'appointment' THEN 'Appointment'
    WHEN 'remove' THEN 'Remove'
    ELSE action
  END AS action_display,
  CASE clarity_level
    WHEN 'complete' THEN 'Complete'
    WHEN 'partial' THEN 'Partial'
    WHEN 'incomplete' THEN 'Incomplete'
    WHEN 'empty' THEN 'Empty'
    ELSE clarity_level
  END AS clarity_display
FROM v_instruction_clarity;
```

## Common Errors

### Error: "cannot drop columns from view"
**Cause:** Using CREATE OR REPLACE when columns have changed
**Fix:** DROP the view first, then CREATE

### Error: "relation does not exist"
**Cause:** Dependent view references a dropped base view
**Fix:** Drop dependents first, recreate base, then recreate dependents

### Error: "column X does not exist"
**Cause:** Dependent view references column not in new base view definition
**Fix:** Ensure base view includes ALL columns that dependents need

## Verification Queries

After updating, verify with:

```sql
-- Check new distribution
SELECT
  clarity_level,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM v_instruction_clarity
GROUP BY clarity_level
ORDER BY
  CASE clarity_level
    WHEN 'complete' THEN 1
    WHEN 'partial' THEN 2
    WHEN 'incomplete' THEN 3
    WHEN 'empty' THEN 4
  END;

-- Verify v_instruction_log works
SELECT * FROM v_instruction_log LIMIT 5;
```

## Reference: reactivations Table Columns

```
id, execution_id, location_id, dealership_name, dealership_hours,
dealership_timezone, contact_id, lead_name, lead_first_name, lead_phone,
lead_email, lead_type, assigned_rep_id, rep_name, instruction,
instruction_raw, instruction_length, instruction_word_count, action,
follow_up_message, follow_up_date, appointment_type, appointment_time,
appointment_summary, ghl_appointment_id, drive_context, tasks_completed_count,
reactivated_at, created_at, updated_at, source_workflow, raw_data
```
