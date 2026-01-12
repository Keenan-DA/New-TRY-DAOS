-- Run this to see what triggers exist
SELECT trigger_name, event_object_table as on_table, event_manipulation as event
FROM information_schema.triggers
WHERE trigger_schema = 'public';
