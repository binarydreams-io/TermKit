# Performance Baseline

## Accepted Baseline

- Date: 2026-08-13
- Revision: `uncommitted` because this imported workspace has no Git `HEAD`
- Configuration: release
- Swift: Apple Swift 6.3.3
- Target: `arm64-apple-macosx26.0`
- Kernel: Darwin 25.4.0
- Hardware: Mac15,6, Apple M3 Pro, 11 logical CPUs, 19,327,352,832 bytes of memory
- Terminal: Ghostty 1.3.1
- Command: `SWIFTTUI_RUN_PERFORMANCE_TESTS=1 swift test -c release --filter TUIPerformanceTests`

## Accepted Matrix

Each row maps one Section 15 gate to a test, an enforced limit, and the accepted result.

| Gate | Test identifier | Budget or invariant | Accepted result |
| --- | --- | --- | --- |
| `localized-frame` | `TUIPerformanceTests.RenderPipelinePerformanceTests/localizedAnimation()` | p95 < 8 ms for a localized 120x40 frame | 0.0 ms p95 |
| `full-repaint` | `TUIPerformanceTests.RenderPipelinePerformanceTests/fullRepaint()` | p95 < 16.67 ms for a 200x60 repaint | 0.3 ms p95 |
| `unchanged-frame` | `TUIPerformanceTests.RenderPipelinePerformanceTests/unchangedFrame()` | zero paint passes, operations, and writes | zero paint passes, operations, and writes |
| `idle-wakeup` | `TUIPerformanceTests.IdleSystemTests/noPeriodicIdleWake()` | no event before the explicit wake during 100 ms | no event during 100 ms |
| `ordinary-write` | `TUIPerformanceTests.RenderPipelinePerformanceTests/oneLogicalWrite()` | exactly one logical write for one changed frame | one logical write |
| `lazy-transcript` | `TUIPerformanceTests.ScalabilityPerformanceTests/lazyConversation()` | p95 < 8 ms and at most 24 mounted rows for 10,000 items | 0.4 ms p95 and at most 24 rows |
| `local-tool-row` | `TUIPerformanceTests.ScalabilityPerformanceTests/localToolRowMutation()` | p95 < 8 ms with one layout pass and one paint pass | contract passed, measured p95 was below 0.1 ms |
| `bounded-interner` | `TUIPerformanceTests.ScalabilityPerformanceTests/boundedInternerRebuild()` | at most 16 entries and 2,048 bytes before controlled rebuild | 8-entry trigger rebuilt to 2 live entries |
| `bounded-frame-queue` | `TUIPerformanceTests.SchedulerPerformanceTests/coalescing()` | 100,000 invalidations produce one frame and no queued frame | one frame and no queued frame |
| `bounded-frame-queue` | `TUIPerformanceTests.SchedulerPerformanceTests/noStaleQueue()` | a stalled animation produces no stale queued frame | no stale queued frame |
| `idle-wakeup` | `TUIPerformanceTests.SchedulerPerformanceTests/idleHasNoDeadline()` | an idle scheduler has no frame or deadline | no frame or deadline |
| `localized-frame` | `TUIPerformanceTests.RenderPipelinePerformanceTests/declarativePaintAnimation()` | p95 < 8 ms with no reconciliation or layout | 2.1 ms p95 with no reconciliation or layout |
| `local-tool-row` | `TUIPerformanceTests.ScalabilityPerformanceTests/oneRowDamage()` | exactly one 120-cell row is scanned and painted | 120 cells scanned and painted |

All 13 performance tests passed in the accepted run.

These results measure the deterministic in-process runtime and presentation pipeline. They exclude terminal compositor latency. The release process runs the Ghostty smoke scenario and records visual tearing separately.
