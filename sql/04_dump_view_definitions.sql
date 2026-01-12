-- ============================================
-- DUMP ALL VIEW DEFINITIONS
-- This shows the actual SQL code inside each view
-- ============================================

-- QUERY 1: Get v_cs_account_health definition (the main broken view)
SELECT
    'v_cs_account_health' as view_name,
    pg_get_viewdef('v_cs_account_health'::regclass, true) as view_definition;

-- QUERY 2: Get ALL view definitions in one query
SELECT
    viewname as view_name,
    definition as view_sql
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;

-- QUERY 3: Check for missing indexes on key tables
SELECT
    t.relname as table_name,
    i.relname as index_name,
    a.attname as column_name
FROM pg_class t
JOIN pg_index ix ON t.oid = ix.indrelid
JOIN pg_class i ON i.oid = ix.indexrelid
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
WHERE t.relkind = 'r'
AND t.relname IN ('leads', 'tasks', 'reactivations', 'appointments', 'ai_decisions', 'task_completions')
ORDER BY t.relname, i.relname;

-- QUERY 4: Table sizes to understand scale
SELECT
    relname as table_name,
    n_live_tup as row_count,
    pg_size_pretty(pg_total_relation_size(relid)) as total_size
FROM pg_stat_user_tables
WHERE relname IN ('leads', 'tasks', 'reactivations', 'appointments', 'ai_decisions', 'task_completions')
ORDER BY n_live_tup DESC;

-- QUERY 5: Check if views reference each other (nested views cause slowness)
SELECT
    v.viewname as view_name,
    CASE
        WHEN v.definition LIKE '%v_%' THEN 'References other views'
        ELSE 'Direct table queries'
    END as complexity
FROM pg_views v
WHERE v.schemaname = 'public'
AND v.viewname LIKE 'v_%'
ORDER BY v.viewname;
