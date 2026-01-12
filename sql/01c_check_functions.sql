-- Run this to see what functions exist
SELECT routine_name, data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_type = 'FUNCTION'
ORDER BY routine_name;
