-- ============================================
-- DA-OS SUPABASE DIAGNOSTIC CHECK
-- Run this in Supabase SQL Editor and share results
-- ============================================

-- QUERY 1: List all tables with row counts
SELECT
    'TABLES' as check_type,
    t.table_name,
    (
        SELECT COUNT(*)::text
        FROM information_schema.columns c
        WHERE c.table_name = t.table_name AND c.table_schema = 'public'
    ) as column_count
FROM information_schema.tables t
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY t.table_name;

-- QUERY 2: List all views
SELECT
    'VIEWS' as check_type,
    table_name as view_name,
    '' as notes
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

-- QUERY 3: List all functions
SELECT
    'FUNCTIONS' as check_type,
    routine_name as function_name,
    data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_type = 'FUNCTION'
ORDER BY routine_name;

-- QUERY 4: List all triggers
SELECT
    'TRIGGERS' as check_type,
    trigger_name,
    event_object_table as on_table,
    event_manipulation as event_type
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table;

-- QUERY 5: Get row counts for expected tables (run each separately if needed)
SELECT 'leads' as table_name, COUNT(*) as row_count FROM leads
UNION ALL SELECT 'tasks', COUNT(*) FROM tasks
UNION ALL SELECT 'reactivations', COUNT(*) FROM reactivations
UNION ALL SELECT 'appointments', COUNT(*) FROM appointments
UNION ALL SELECT 'ai_decisions', COUNT(*) FROM ai_decisions
UNION ALL SELECT 'task_completions', COUNT(*) FROM task_completions
UNION ALL SELECT 'lead_source_dictionary', COUNT(*) FROM lead_source_dictionary;
