-- ============================================
-- CHECK VIEW COLUMN STRUCTURES
-- Run each query to see what columns each view has
-- ============================================

-- QUERY 1: v_cs_account_health columns (main dashboard view)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_cs_account_health'
ORDER BY ordinal_position;

-- QUERY 2: v_pipeline_funnel columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_pipeline_funnel'
ORDER BY ordinal_position;

-- QUERY 3: v_rep_complete_scorecard columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_rep_complete_scorecard'
ORDER BY ordinal_position;

-- QUERY 4: v_instruction_log columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_instruction_log'
ORDER BY ordinal_position;

-- QUERY 5: v_lost_opportunity columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_lost_opportunity'
ORDER BY ordinal_position;

-- QUERY 6: v_pipeline_funnel_by_source columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_pipeline_funnel_by_source'
ORDER BY ordinal_position;
