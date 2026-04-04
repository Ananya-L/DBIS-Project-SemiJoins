# Data Volume Estimate

This document is generated from `scripts/data_volume_estimator.sql` and helps quantify the network transfer advantage of semijoin-style filtering.

## What it estimates

1. Approximate remote row width in bytes.
2. Approximate remote-transfer volume for the latest strategy runs.
3. Estimated megabytes saved by filtering before join.
4. Estimated percentage reduction.

## Why it matters

Even when execution time varies by machine, transfer-volume reduction is a strong explanation for why semijoin can be beneficial in distributed settings.

## Recommended use

1. Run the estimator after benchmarks.
2. Use the MB saved value in your viva.
3. Pair it with the selectivity profile and elite showcase.
