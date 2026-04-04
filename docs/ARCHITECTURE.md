# Architecture Diagram

```mermaid
flowchart LR
    A1[Site A\nPostgreSQL Coordinator] -->|FDW query| B1[Site B\nPostgreSQL Remote]

    subgraph SA[Site A Components]
      AL[a_local]
      FT[b_remote_ft]\nFDW mapping
      F1[fetch_b_semijoin]\nBatched ANY
      F2[fetch_b_semijoin_staged]\nRemote staging join
      F3[fetch_b_semijoin_auto]\nAdaptive selector
      BM[benchmark_semijoin_strategies]\nrun_and_log_benchmark
      LOG[(semijoin_run_metrics)]
      TUNE[(semijoin_tuning_history)]
    end

    subgraph SB[Site B Components]
      BR[b_remote]
      ST[semijoin_keys_stage]
    end

    FT --> BR
    F1 --> FT
    F2 --> ST
    F2 --> FT
    F3 --> F1
    F3 --> F2
    F3 --> FT
    BM --> LOG
    BM --> F1
    BM --> F2
    BM --> FT
    A1 --> BM
    A1 --> F3
```

## Data Flow

1. Local join keys are derived from `a_local`.
2. Strategy is selected manually or by `fetch_b_semijoin_auto`.
3. Remote tuples are fetched from `b_remote` either by direct scan, batched key filtering, or staged remote join.
4. Final join is completed at Site A.
5. Metrics and tuning history are recorded for reproducibility and calibration.
