-- Run this to see what views exist
SELECT table_name as view_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;
