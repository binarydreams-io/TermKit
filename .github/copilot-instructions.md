# Copilot Instructions for SwiftTUI

## Project

SwiftTUI is a declarative terminal UI framework for macOS and Linux. The `TUIkit*` targets and related tools are internal regression and provenance evidence. Do not present them as public products or compatibility goals.

## Hard Constraints

- Use exactly Swift 6.0.3 and `swift-tools-version: 6.0`.
- Support macOS 14 or later and the pinned glibc Linux image.
- Do not use APIs or language features from newer Swift releases.
- Treat compiler and DocC warnings as errors.
- Run SwiftLint with `--strict --no-cache`.
- Preserve Linux behavior. Do not add Apple-only behavior without a guarded cross-platform implementation.

## Commands

```bash
# Focused development checks
swift build -Xswiftc -warnings-as-errors
swift test --filter <TestSuiteName>

# Complete macOS and Linux gate
./scripts/test-linux.sh

# Release performance gate for runtime, renderer, layout, or animation changes
./scripts/swifttui-benchmark.sh
```

## Current Architecture

SwiftTUI views implement `graphBody` and produce `NodeDescriptor` values. The declarative runtime reconciles those values into a retained `ViewGraph`.

Retained primitives own stable identity, state, dependencies, layout data, paint bounds, and lifecycle state. Apply the narrowest invalidation level:

- `paint` for visual changes that preserve geometry.
- `layout` for measurement or placement changes.
- `structure` when `graphBody` or child identity changes.

Do not introduce the legacy `body: some View`, `Renderable`, `RenderContext`, or `FrameBuffer` model into SwiftTUI modules.

## Module Direction

Dependencies point from higher layers to lower layers:

1. `TUIFoundation`
2. `TUITerminal`, `TUIRenderer`
3. `TUIViewGraph`, `TUILayout`, `TUIAnimation`
4. `TUIControls`, `TUIDesign`, `TUIRichText`, `TUIAgentUI`
5. `TUIRuntime`, `SwiftTUI`

Keep POSIX I/O in `TUITerminal`, surfaces and ANSI output in `TUIRenderer`, reconciliation in `TUIViewGraph`, layout in `TUILayout`, and frame orchestration in `TUIRuntime`. Lower layers must not import higher layers or the umbrella module.

## Implementation Rules

- Search for an existing pattern before adding a type or function.
- Prefer declarative composition and retained primitives over parallel rendering paths.
- Preserve structural identity across reconciliation.
- Keep graph and rendering work on the UI actor.
- Coalesce invalidations and avoid idle frame timers.
- Add focused tests in the target that matches the changed module.
- Run `SwiftTUIIntegrationTests` for umbrella or runtime integration changes.
- Run `TUIPerformanceTests` through `./scripts/swifttui-benchmark.sh` for runtime or rendering changes.

## Legacy TUIkit Regression

Legacy TUIkit targets, vendored image codecs, and `Tools/APICompatibility` remain only as internal regression fixtures and provenance records. They do not define current SwiftTUI architecture or public API parity.

Preserve legacy image checks for pure Swift PNG and JPEG decoding, bounded allocation, non-premultiplied 8-bit RGBA output, namespaced imports, licenses, and macOS/Linux support.

## Code Style

- Use four-space indentation.
- Use trailing commas in multiline collections.
- Follow `.swiftlint.yml` and `.swift-format`.
- Do not merge pull requests autonomously.
