# Command Center

The command center script orchestrates the most important project validation and evidence-generation steps in one run.

## Script

- `scripts/command_center.ps1`

## What it runs

1. Environment sanity check
2. Quality gate
3. Data volume estimator
4. Benchmark diff
5. Evidence index generation
6. Release notes generation

## Output

- `reports/command_center_<timestamp>.json`

## Why it matters

Use this when you want a single high-confidence snapshot that the project is healthy, the evidence is current, and the submission artifacts are ready.
