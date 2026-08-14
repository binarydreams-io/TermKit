# Benchmarks

TermKit preserves 13 deterministic performance contracts for scheduling, rendering, invalidation, and scale.
The pull-request gate checks invariants instead of unstable hosted-runner timing thresholds.

Run the benchmark wrapper:

```bash
./scripts/run-benchmarks.sh
```

The wrapper emits `metadata.json`, `results.json`, and the complete test log.
The metadata records the revision, Swift version, platform, environment, and command.
Scheduled and manual runs can compare timing data on known hardware.
The repository baseline is in `Documentation/benchmark-baseline.json`.

The contracts cover these areas:

- idle scheduler behavior;
- frame cadence and coalescing;
- bounded damage and diff scanning;
- unchanged-frame suppression;
- graph and layout invalidation scope;
- bounded lazy viewport work;
- bounded interner rebuilding;
- retained rendering and offscreen surfaces;
- wide-cell correctness under randomized operations.
