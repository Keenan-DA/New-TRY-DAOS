-- Run this FIRST to see what tables exist
SELECT
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns c
     WHERE c.table_name = t.table_name AND c.table_schema = 'public') as columns
FROM information_schema.tables t
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY table_name;
