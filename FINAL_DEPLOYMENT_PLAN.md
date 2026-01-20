# Final Deployment Plan - Drive AI 7.0 Supabase Fix

**Date:** January 20, 2026
**Status:** Ready for Deployment

---

## Executive Summary

After comprehensive testing of the Supabase database and HTML dashboard, I identified **3 missing views** and **1 broken function**. All issues are fixable with a single SQL file.

---

## Issues Found

### Critical Issues (Dashboard Broken)

| Issue | Impact | Root Cause |
|-------|--------|------------|
| `v_rep_complete_scorecard` missing | Rep scorecard table doesn't load | View never created |
| `v_health_trend` missing | Health trend charts unavailable | View never created |
| `v_rep_instruction_quality` missing | Rep instruction analysis unavailable | View never created |

### Data Flow Issues (From Other Branch)

| Issue | Impact | Root Cause |
|-------|--------|------------|
| `insert_appointment` fails | New AI appointments not saved | Function missing `p_appt_valid` parameter |

---

## Branch Status

| Branch | Contents | Status |
|--------|----------|--------|
| `claude/test-supabase-data-DI04d` | View tests, basic fix SQL | Current |
| `claude/improve-dashboard-html-ssCuP` | Appointment fixes, date filtering, improved dashboard | Has additional fixes |

---

## Deployment Steps

### Step 1: Run Master SQL Fix

**File:** `MASTER_SUPABASE_FIX.sql`

1. Open Supabase Dashboard → SQL Editor
2. Copy entire contents of `MASTER_SUPABASE_FIX.sql`
3. Run the SQL
4. Verify no errors

This creates:
- `v_rep_complete_scorecard` (view)
- `v_health_trend` (view)
- `v_rep_instruction_quality` (view)
- Fixed `insert_appointment` function

### Step 2: Verify Views Work

Run these queries in SQL Editor:

```sql
-- Test 1: Rep Scorecard (should return data)
SELECT * FROM v_rep_complete_scorecard LIMIT 5;

-- Test 2: Health Trend (should return weekly data)
SELECT * FROM v_health_trend WHERE week >= NOW() - INTERVAL '30 days' LIMIT 10;

-- Test 3: Rep Instruction Quality
SELECT * FROM v_rep_instruction_quality LIMIT 5;
```

### Step 3: Test Dashboard

1. Open the dashboard HTML file
2. Click on any dealership
3. Verify:
   - Rep Scorecard table loads
   - Pipeline stats show
   - Instruction log appears
   - No errors in browser console

### Step 4: (Optional) Merge Additional Fixes

If you want the improved dashboard with pagination and date filtering:

```bash
git checkout claude/test-supabase-data-DI04d
git merge claude/improve-dashboard-html-ssCuP
```

This brings in:
- Enhanced `DA-OS (4).html` with pagination
- `SUPABASE_DATE_FILTERING.sql` for server-side filtering
- `FINAL_APPOINTMENT_FIX.sql` (already in master fix)

---

## HTML vs View Column Mapping

### v_cs_account_health → Dashboard Portfolio

| HTML Expects | View Returns | Status |
|--------------|--------------|--------|
| `location_id` | `location_id` | ✅ Match |
| `dealership_name` | `dealership_name` | ✅ Match |
| `adoption_score` | `adoption_score` | ✅ Match |
| `compounding_rate` | `compounding_rate` | ✅ Match |
| `closed_loop_score` | `closed_loop_score` | ✅ Match |
| `clarity_score` | `clarity_score` | ✅ Match |
| `marking_score` | `marking_score` | ✅ Match |
| `overdue_tasks` | `overdue_tasks` | ✅ Match |
| `total_tasks` | `total_tasks` | ✅ Match |
| `completed_tasks` | `completed_tasks` | ✅ Match |

### v_rep_complete_scorecard → Rep Table

| HTML Expects | View Returns | Status |
|--------------|--------------|--------|
| `rep_name` | `rep_name` | ✅ Match |
| `total_tasks` | `total_tasks` | ✅ Match |
| `completed_tasks` | `completed_tasks` | ✅ Match |
| `closed_loop_pct` | `closed_loop_pct` | ✅ Match |
| `clarity_pct` | `clarity_pct` | ✅ Match |
| `performance_status` | `performance_status` | ✅ Match |

### v_instruction_log → Instruction Log

| HTML Expects | View Returns | Status |
|--------------|--------------|--------|
| `rep_name` or `assigned_rep_name` | Both | ✅ Match |
| `lead_name` | `lead_name` | ✅ Match |
| `action` | `action` | ✅ Match |
| `clarity_level` | `clarity_level` | ✅ Match |
| `has_context/action/timing` | All present | ✅ Match |
| `instruction` | `instruction` | ✅ Match |
| `follow_up_message/date` | Both present | ✅ Match |
| `appointment_time/summary` | Both present | ✅ Match |

### v_pipeline_funnel → Pipeline Stats

| HTML Expects | View Returns | Status |
|--------------|--------------|--------|
| `reply_rate` | `reply_rate` | ✅ Match |
| `booking_rate` | `booking_rate` | ✅ Match |
| `show_rate` | `show_rate` | ✅ Match |
| `past_appointments` | `past_appointments` | ✅ Match |
| `showed` | `showed` | ✅ Match |
| `no_shows` | `no_shows` | ✅ Match |
| `unmarked_appointments` | `unmarked_appointments` | ✅ Match |

### v_pipeline_funnel_by_source → Source Table

| HTML Expects | View Returns | Status |
|--------------|--------------|--------|
| `lead_source` | `lead_source` | ✅ Match |
| `total_leads` | `total_leads` | ✅ Match |
| `reply_rate` | `reply_rate` | ✅ Match |
| `booking_rate` | `booking_rate` | ✅ Match |
| `show_rate` | `show_rate` | ✅ Match |

---

## Data Integrity Summary

| Table | Records | Status |
|-------|---------|--------|
| leads | 76,237 | ✅ OK |
| tasks | 26,962 | ✅ OK |
| reactivations | 22,213 | ✅ OK |
| appointments | 3,160 | ✅ OK |
| ai_decisions | 14,443 | ✅ OK |
| task_completions | 9,212 | ✅ OK |

---

## Files in This Repository

| File | Purpose |
|------|---------|
| `MASTER_SUPABASE_FIX.sql` | **RUN THIS** - All-in-one fix |
| `SUPABASE_VIEW_FIXES.sql` | Views only (subset of master) |
| `SUPABASE_TEST_RESULTS.md` | Test results documentation |
| `FINAL_DEPLOYMENT_PLAN.md` | This document |
| `DA-OS (4).html` | Dashboard (current version) |

---

## Quick Checklist

- [ ] Run `MASTER_SUPABASE_FIX.sql` in Supabase SQL Editor
- [ ] Verify `v_rep_complete_scorecard` returns data
- [ ] Verify `v_health_trend` returns data
- [ ] Verify `v_rep_instruction_quality` returns data
- [ ] Test dashboard loads without errors
- [ ] Test clicking on a dealership shows rep scorecard

---

## Troubleshooting

### "View already exists"
The SQL uses `DROP VIEW IF EXISTS` so this shouldn't happen. If it does, manually drop:
```sql
DROP VIEW IF EXISTS v_rep_complete_scorecard CASCADE;
DROP VIEW IF EXISTS v_health_trend CASCADE;
DROP VIEW IF EXISTS v_rep_instruction_quality CASCADE;
```

### "Permission denied"
Make sure you're running as a user with admin rights, or run the GRANT statements separately:
```sql
GRANT SELECT ON v_rep_complete_scorecard TO anon, authenticated, service_role;
GRANT SELECT ON v_health_trend TO anon, authenticated, service_role;
GRANT SELECT ON v_rep_instruction_quality TO anon, authenticated, service_role;
```

### Dashboard still shows errors
1. Check browser console for specific error
2. Verify view returns data: `SELECT * FROM v_rep_complete_scorecard LIMIT 1;`
3. Clear browser cache and reload

---

## Contact

All files committed to branch: `claude/test-supabase-data-DI04d`

*Plan created: January 20, 2026*
