# Pipeline View Deployment Guide

## What Was Changed

### 1. Pipeline Performance Section
- **Internet Leads**: Total leads excluding walk-in, phone-up, drive-by sources
- **Appointments**: Count with booking rate percentage
- **Showed**: Count with show rate (noted as "on marked appts")
- **No-Shows**: Count with no-show rate
- **Appointment Marking Status**: Summary of marked/unmarked
- **Speed to Lead**: Clean formatted metric

### 2. Rep Leaderboard
- Tasks (total/completed/overdue)
- Appointments (total/showed)
- Loop %, Quality %, Marking Rate
- Power User badges (loop >= 85%, clarity >= 70%)
- Rising Star badges (loop >= 70%, clarity >= 60%)
- Needs Training badges (loop < 50% or clarity < 40%)
- Focus areas for underperformers

---

## Deployment Options

### Option A: Simple File Hosting (Recommended)

The dashboard is a single HTML file. Just host it anywhere:

1. **GitHub Pages** (Free)
   ```bash
   # If your repo is public, enable GitHub Pages in Settings > Pages
   # Select branch: main, folder: / (root)
   # Access at: https://[username].github.io/[repo-name]/DA-OS%20(4).html
   ```

2. **Netlify** (Free)
   - Drag and drop the HTML file at https://app.netlify.com/drop
   - Or connect your GitHub repo for auto-deploys

3. **Vercel** (Free)
   - Import your GitHub repo at https://vercel.com/import
   - Auto-deploys on push

4. **Local Testing**
   ```bash
   # Just open the file in a browser
   open "DA-OS (4).html"
   # Or use a local server
   python -m http.server 8000
   # Then visit: http://localhost:8000/DA-OS%20(4).html
   ```

### Option B: Existing Hosting

If you already have hosting, just replace the old HTML file with the new one.

---

## Supabase Requirements

### Required Views (Already Exist)
The dashboard uses these views that should already exist in your Supabase:

| View | Purpose |
|------|---------|
| `v_cs_account_health` | Account overview, health scores |
| `v_pipeline_funnel` | Lead-to-show conversion metrics |
| `v_pipeline_funnel_by_source` | Lead source breakdown |
| `v_rep_complete_scorecard` | Rep performance metrics |
| `v_rep_appointment_breakdown` | Rep appointment marking data |
| `v_instruction_log` | Instruction log entries |
| `v_lost_opportunity` | Lost opportunity analysis |

### Check Your Views
Run this in Supabase SQL Editor to verify:

```sql
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
AND table_name IN (
  'v_cs_account_health',
  'v_pipeline_funnel',
  'v_pipeline_funnel_by_source',
  'v_rep_complete_scorecard',
  'v_rep_appointment_breakdown',
  'v_instruction_log',
  'v_lost_opportunity'
);
```

All 7 views should appear. If any are missing, you'll need to create them per your SUPABASE_SCHEMA.md documentation.

---

## Optional: Update v_rep_complete_scorecard

If you want to simplify the code and avoid the client-side merge, you can update the `v_rep_complete_scorecard` view to include marking data:

```sql
-- Drop existing view
DROP VIEW IF EXISTS v_rep_complete_scorecard;

-- Recreate with marking data included
CREATE OR REPLACE VIEW v_rep_complete_scorecard AS
WITH task_stats AS (
  SELECT
    location_id,
    assigned_rep_id,
    assigned_rep_name,
    COUNT(*) as total_tasks,
    COUNT(*) FILTER (WHERE completed = true) as completed_tasks,
    COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) as overdue_tasks,
    CASE
      WHEN COUNT(*) FILTER (WHERE completed = true) + COUNT(*) FILTER (WHERE completed = false AND due_date < NOW()) > 0
      THEN ROUND(100.0 * COUNT(*) FILTER (WHERE completed = true) /
           (COUNT(*) FILTER (WHERE completed = true) + COUNT(*) FILTER (WHERE completed = false AND due_date < NOW())), 0)
      ELSE 100
    END as closed_loop_pct,
    AVG(EXTRACT(EPOCH FROM (r.reactivated_at - t.created_at))/3600) FILTER (WHERE completed = true) as avg_hours_to_close
  FROM tasks t
  LEFT JOIN reactivations r ON t.completed_by_reactivation_id = r.id
  GROUP BY location_id, assigned_rep_id, assigned_rep_name
),
instruction_stats AS (
  SELECT
    location_id,
    assigned_rep_id,
    COUNT(*) as total_instructions,
    COUNT(*) FILTER (WHERE clarity_level = 'complete') as complete_instructions,
    COUNT(*) FILTER (WHERE clarity_level = 'partial') as partial_instructions,
    COUNT(*) FILTER (WHERE clarity_level IN ('incomplete', 'empty')) as low_instructions,
    CASE
      WHEN COUNT(*) FILTER (WHERE clarity_level != 'empty') > 0
      THEN ROUND(100.0 * COUNT(*) FILTER (WHERE clarity_level = 'complete') /
           COUNT(*) FILTER (WHERE clarity_level != 'empty'), 0)
      ELSE 0
    END as clarity_pct
  FROM v_instruction_clarity
  GROUP BY location_id, assigned_rep_id
),
appointment_stats AS (
  SELECT
    location_id,
    assigned_rep_id,
    COUNT(*) as total_appointments,
    COUNT(*) FILTER (WHERE created_source = 'rep_instructed') as rep_booked_appointments,
    COUNT(*) FILTER (WHERE appointment_time < NOW()) as past_appointments,
    COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status != 'pending') as marked_appointments,
    COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status = 'pending') as unmarked_appointments,
    COUNT(*) FILTER (WHERE outcome_status = 'showed') as showed,
    COUNT(*) FILTER (WHERE outcome_status = 'no_show') as no_shows,
    CASE
      WHEN COUNT(*) FILTER (WHERE outcome_status IN ('showed', 'no_show')) > 0
      THEN ROUND(100.0 * COUNT(*) FILTER (WHERE outcome_status = 'showed') /
           COUNT(*) FILTER (WHERE outcome_status IN ('showed', 'no_show')), 0)
      ELSE NULL
    END as show_rate,
    CASE
      WHEN COUNT(*) FILTER (WHERE appointment_time < NOW()) > 0
      THEN ROUND(100.0 * COUNT(*) FILTER (WHERE appointment_time < NOW() AND outcome_status != 'pending') /
           COUNT(*) FILTER (WHERE appointment_time < NOW()), 0)
      ELSE NULL
    END as marking_rate
  FROM appointments
  GROUP BY location_id, assigned_rep_id
)
SELECT
  COALESCE(t.location_id, i.location_id, a.location_id) as location_id,
  COALESCE(t.assigned_rep_id, i.assigned_rep_id, a.assigned_rep_id) as rep_id,
  COALESCE(t.assigned_rep_name, 'Unknown') as rep_name,
  COALESCE(t.total_tasks, 0) as total_tasks,
  COALESCE(t.completed_tasks, 0) as completed_tasks,
  COALESCE(t.overdue_tasks, 0) as overdue_tasks,
  COALESCE(t.closed_loop_pct, 100) as closed_loop_pct,
  t.avg_hours_to_close,
  COALESCE(i.total_instructions, 0) as total_instructions,
  COALESCE(i.complete_instructions, 0) as complete_instructions,
  COALESCE(i.partial_instructions, 0) as partial_instructions,
  COALESCE(i.low_instructions, 0) as low_instructions,
  COALESCE(i.clarity_pct, 0) as clarity_pct,
  COALESCE(a.total_appointments, 0) as total_appointments,
  COALESCE(a.rep_booked_appointments, 0) as rep_booked_appointments,
  COALESCE(a.past_appointments, 0) as past_appointments,
  COALESCE(a.marked_appointments, 0) as marked_appointments,
  COALESCE(a.unmarked_appointments, 0) as unmarked_appointments,
  COALESCE(a.showed, 0) as showed,
  COALESCE(a.no_shows, 0) as no_shows,
  a.show_rate,
  a.marking_rate,
  CASE
    WHEN COALESCE(t.closed_loop_pct, 100) >= 85 AND COALESCE(i.clarity_pct, 0) >= 70 THEN 'EXCELLENT'
    WHEN COALESCE(t.closed_loop_pct, 100) >= 70 AND COALESCE(i.clarity_pct, 0) >= 50 THEN 'GOOD'
    WHEN COALESCE(t.closed_loop_pct, 100) >= 50 THEN 'FAIR'
    ELSE 'NEEDS_COACHING'
  END as performance_status
FROM task_stats t
FULL OUTER JOIN instruction_stats i ON t.location_id = i.location_id AND t.assigned_rep_id = i.assigned_rep_id
FULL OUTER JOIN appointment_stats a ON COALESCE(t.location_id, i.location_id) = a.location_id
  AND COALESCE(t.assigned_rep_id, i.assigned_rep_id) = a.assigned_rep_id;
```

**Note:** The SQL above is a template. Your actual view may have different table structures. Refer to your SUPABASE_SCHEMA.md for the exact implementation.

---

## Verify Deployment

After deploying, test:

1. Load the dashboard - should show the portfolio view
2. Click on a client - should load client detail
3. Check Pipeline Performance section - should show Internet Leads, Appointments, Showed, No-Shows
4. Check Rep Leaderboard - should show badges and focus areas
5. Check browser console (F12) for any errors

---

## Troubleshooting

### "Failed to fetch" errors
- Check Supabase URL and API key in the HTML file
- Verify Row Level Security (RLS) policies allow reads

### Missing data in leaderboard
- Verify `v_rep_appointment_breakdown` view exists
- Check if there are appointments for the selected client

### No internet leads showing
- Check `v_pipeline_funnel_by_source` has data
- Verify lead sources don't all match the excluded list

---

## Files Changed

| File | Changes |
|------|---------|
| `DA-OS (4).html` | Pipeline view + rep leaderboard updates |
| `DEPLOYMENT_GUIDE.md` | This file |
