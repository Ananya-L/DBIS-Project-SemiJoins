\timing on

-- Ensure function exists from advanced tools script, then run tuner.
SELECT *
FROM autotune_semijoin_thresholds(5, 500);

SELECT tune_id,
       tune_ts,
       rounds,
       chunk_size,
       distinct_keys,
       best_strategy,
       best_avg_ms,
       recommended_batch_threshold,
       recommended_staged_threshold
FROM semijoin_tuning_history
ORDER BY tune_id DESC
LIMIT 10;
