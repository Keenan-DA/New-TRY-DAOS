# Supabase Database Test Results

**Test Date:** January 20, 2026
**Tested By:** Claude
**Database:** https://gamwimamcvgakcetdypm.supabase.co

---

## Executive Summary

Tested all 37+ documented views against the Supabase database. Found **3 missing views** that are documented but not created in the database. The dashboard queries one of these missing views (`v_rep_complete_scorecard`), which is causing errors.

**Overall Status:** 🟡 PARTIALLY BROKEN

---

## Missing Views (CRITICAL)

| View Name | Status | Impact | Fix Available |
|-----------|--------|--------|---------------|
| `v_rep_complete_scorecard` | ❌ MISSING | **Dashboard broken** - Rep scorecard doesn't load | Yes - `SUPABASE_VIEW_FIXES.sql` |
| `v_health_trend` | ❌ MISSING | Trend tracking unavailable | Yes - `SUPABASE_VIEW_FIXES.sql` |
| `v_rep_instruction_quality` | ❌ MISSING | Rep instruction analysis unavailable | Yes - `SUPABASE_VIEW_FIXES.sql` |

---

## Working Views (34/37)

### Dashboard-Critical Views (All Working)
| View | Status | Description |
|------|--------|-------------|
| `v_cs_account_health` | ✅ OK | Main portfolio health view |
| `v_lost_opportunity` | ✅ OK | Lost opportunity analysis |
| `v_pipeline_funnel` | ✅ OK | Lead-to-show conversion funnel |
| `v_pipeline_funnel_by_source` | ✅ OK | Pipeline metrics by source |
| `v_instruction_log` | ✅ OK | Instruction activity log |

### Reference Views
| View | Status | Description |
|------|--------|-------------|
| `v_dealerships` | ✅ OK | Dealership dropdown list |
| `v_reps` | ✅ OK | Rep dropdown list |
| `v_source_map` | ✅ OK | Source normalization mapping |

### Pipeline & Funnel Views
| View | Status | Description |
|------|--------|-------------|
| `v_lead_pipeline` | ✅ OK | Complete lead journey |
| `v_lead_funnel` | ✅ OK | Funnel metrics |
| `v_funnel_metrics` | ✅ OK | Detailed funnel with speed |
| `v_conversion_funnel` | ✅ OK | Aggregate funnel by dealership |
| `v_conversion_by_source` | ✅ OK | Funnel by lead source |
| `v_source_performance` | ✅ OK | Source quality scoring |
| `v_lead_funnel_summary` | ✅ OK | Summary metrics |

### Task & Loop Closure Views
| View | Status | Description |
|------|--------|-------------|
| `v_loop_closure_stats` | ✅ OK | Task completion metrics |
| `v_overdue_tasks` | ✅ OK | Uncompleted tasks past due |
| `v_task_efficiency` | ✅ OK | Tasks per lead ratio |

### Instruction Quality Views
| View | Status | Description |
|------|--------|-------------|
| `v_instruction_clarity` | ✅ OK | Individual instruction scoring |
| `v_instruction_quality` | ✅ OK | Legacy instruction quality |
| `v_instruction_quality_by_rep` | ✅ OK | Quality by rep (legacy) |

### Appointment Views
| View | Status | Description |
|------|--------|-------------|
| `v_appointment_stats` | ✅ OK | Appointment metrics by dealership |
| `v_rep_appointment_breakdown` | ✅ OK | Per-rep appointment metrics |
| `v_ai_human_ratio` | ✅ OK | AI vs human appointment balance |
| `v_upcoming_appointments` | ✅ OK | Future appointments |
| `v_unmarked_appointments` | ✅ OK | Past appointments awaiting outcomes |
| `v_no_shows` | ✅ OK | No-show appointments |
| `v_rep_appointment_stats` | ✅ OK | Appointment metrics per rep |

### Health & Adoption Views
| View | Status | Description |
|------|--------|-------------|
| `v_health_score` | ✅ OK | Overall adoption score |

### Compounding Proof Views
| View | Status | Description |
|------|--------|-------------|
| `v_compounding_metrics` | ✅ OK | Monthly compounding analysis |
| `v_aged_lead_conversions` | ✅ OK | Appointments from aged leads |
| `v_pipeline_growth` | ✅ OK | Pipeline growth MoM |

### Summary Views
| View | Status | Description |
|------|--------|-------------|
| `v_daily_summary` | ✅ OK | Daily activity summary |
| `v_metrics_monthly` | ✅ OK | Monthly rollup of all metrics |
| `v_speed_metrics` | ✅ OK | Speed-to-lead metrics |

---

## Table Data Integrity

All tables contain data and appear to be functioning correctly:

| Table | Row Count | Status |
|-------|-----------|--------|
| `leads` | 76,237 | ✅ OK |
| `tasks` | 26,962 | ✅ OK |
| `reactivations` | 22,213 | ✅ OK |
| `appointments` | 3,160 | ✅ OK |
| `ai_decisions` | 14,443 | ✅ OK |
| `task_completions` | 9,212 | ✅ OK |

### Task Status Distribution
- Completed: 9,212 (34%)
- Pending: 17,751 (66%)

### Reactivation Action Distribution
- Follow-up: 19,862 (89%)
- Appointment: 324 (1.5%)
- Remove: 2,027 (9%)

### Appointment Source Distribution
- AI Automated: 2,953 (93%)
- Rep Instructed: 207 (7%)

### Appointment Outcome Distribution (sample)
- Pending: 693
- Showed: 133
- No-show: 141
- Cancelled: 33

---

## How to Fix

### Step 1: Run the SQL Fix File

Open your Supabase SQL Editor and run the entire contents of:
```
SUPABASE_VIEW_FIXES.sql
```

This will create:
1. `v_rep_complete_scorecard` - Comprehensive rep performance metrics
2. `v_health_trend` - Weekly health score trend over 90 days
3. `v_rep_instruction_quality` - Instruction quality aggregated by rep

### Step 2: Verify the Fixes

After running the SQL, test each view:

```sql
-- Test v_rep_complete_scorecard
SELECT * FROM v_rep_complete_scorecard LIMIT 5;

-- Test v_health_trend
SELECT * FROM v_health_trend WHERE week >= NOW() - INTERVAL '30 days' LIMIT 10;

-- Test v_rep_instruction_quality
SELECT * FROM v_rep_instruction_quality LIMIT 5;
```

### Step 3: Refresh Dashboard

After the views are created, the dashboard should work correctly.

---

## Branch Information

### Current Branch
`claude/test-supabase-data-DI04d`

### Related Branch
`claude/improve-dashboard-html-ssCuP` - Contains additional fixes:
- `FINAL_APPOINTMENT_FIX.sql` - Fixed `insert_appointment` function
- `SUPABASE_DATE_FILTERING.sql` - Server-side date filtering RPCs

### Files Created
- `SUPABASE_VIEW_FIXES.sql` - SQL to create missing views
- `SUPABASE_TEST_RESULTS.md` - This document

---

## Recommendations

1. **Immediate**: Run `SUPABASE_VIEW_FIXES.sql` to fix the dashboard
2. **Consider merging** the `claude/improve-dashboard-html-ssCuP` branch which has additional appointment fixes
3. **Future**: Add automated tests to catch missing views before deployment

---

## Technical Details

### v_rep_complete_scorecard Structure

```sql
-- Key columns:
location_id, assigned_rep_id, rep_name, dealership_name,
total_tasks, completed_tasks, overdue_tasks, pending_not_due,
closed_loop_pct,  -- Uses accountable tasks formula
avg_hours_to_close, median_hours_to_close,
complete_instructions, partial_instructions, low_instructions, clarity_pct,
total_appointments, rep_booked_appointments, showed, no_shows, unworked_no_shows, show_rate,
remove_pct,
performance_status,  -- EXCELLENT/GOOD/FAIR/NEEDS_COACHING
coaching_recommendation
```

### Loop Closure Formula (Accountable Tasks)
```
closed_loop_pct = completed_tasks / (completed_tasks + overdue_tasks) * 100
```
- Only counts tasks that are completed OR past due
- Tasks not yet due don't penalize the score

### Performance Status Logic
| Status | Criteria |
|--------|----------|
| EXCELLENT | ≥85% loop closure AND ≥70% clarity |
| GOOD | ≥70% loop closure AND ≥50% clarity |
| FAIR | ≥50% loop closure |
| NEEDS_COACHING | <50% loop closure |

---

*Test completed: January 20, 2026*
