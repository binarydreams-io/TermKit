# Contributing to SwiftTUI

SwiftTUI is a declarative terminal UI framework for macOS and Linux. The retained TUIkit code supports internal regression and provenance checks. It is not a public product.

## Hard Requirements

| Requirement | Details |
| --- | --- |
| **Swift 6.0.3** | Development and CI use exactly Swift 6.0.3 with `swift-tools-version: 6.0`. Do not use newer compiler features. |
| **macOS and Linux** | Changes must build and run on macOS 14 or later and the pinned glibc Linux image. |
| **Strict checks** | Treat compiler and DocC warnings as errors. Run SwiftLint with `--strict --no-cache`. |

The Linux image, tool versions, and checksums are pinned in `scripts/toolchain.env`.

## Local Quality Gate

Run focused tests while you develop:

```bash
swift build -Xswiftc -warnings-as-errors
swift test --filter <TestSuiteName>
```

Run the complete gate before merge:

```bash
./scripts/test-linux.sh
```

Use a platform argument only for local diagnosis:

```bash
./scripts/test-linux.sh macos
./scripts/test-linux.sh linux
```

The complete gate checks lint, builds, tests, test discovery, DocC, CI configuration, and both supported platforms.

For runtime, renderer, layout, or animation changes, run the release performance gate:

```bash
./scripts/swifttui-benchmark.sh
```

## Architecture

SwiftTUI uses these public modules:

| Layer | Modules |
| --- | --- |
| Base | `TUIFoundation` |
| Platform and rendering | `TUITerminal`, `TUIRenderer` |
| Declarative system | `TUIViewGraph`, `TUILayout`, `TUIAnimation` |
| Components | `TUIControls`, `TUIDesign`, `TUIRichText`, `TUIAgentUI` |
| Runtime and public entry point | `TUIRuntime`, `SwiftTUI` |

Dependencies must point from higher layers to lower layers. Base modules must not import component, runtime, or umbrella modules. The quality gate rejects upward imports.

Views declare `graphBody` and produce `NodeDescriptor` values. The declarative runtime reconciles these values into a retained graph. Do not add the legacy `body: some View`, `Renderable`, or `FrameBuffer` architecture to SwiftTUI modules.

Retained primitives carry stable identity, state, environment dependencies, layout data, paint bounds, and lifecycle state. Use the narrowest correct invalidation level:

- `paint` changes visual output without changing geometry.
- `layout` changes measurement or placement and also requires paint.
- `structure` reevaluates `graphBody` and reconciles children.

Keep terminal I/O in `TUITerminal`, cell and ANSI rendering in `TUIRenderer`, graph ownership in `TUIViewGraph`, and frame orchestration in `TUIRuntime`.

## Testing

- Use Swift Testing with `@Test`, `#expect`, and `@Suite`.
- Put tests in the target that matches the SwiftTUI module.
- Use `SwiftTUIIntegrationTests` for umbrella API and runtime integration coverage.
- Keep independent tests parallel. Serialize only suites that isolate shared state.
- Add focused regression tests for changed behavior.

## Legacy TUIkit Regression

The `TUIkit*` targets, vendored image codecs, and API compatibility tool preserve regression and provenance evidence from the predecessor project. They are internal repository fixtures, not supported SwiftTUI products or public compatibility promises.

Legacy image regression coverage keeps these requirements:

- Decode static PNG and JPEG input to non-premultiplied 8-bit RGBA output.
- Keep vendored decoder sources pure Swift, namespaced, and provenance-documented.
- Support Swift 6.0.3 on macOS and Linux.
- Bound input, dimensions, pixels, frames, samples, and final allocations before decoding.
- Keep decoding separate from file and network lifecycle code.

Changes to legacy evidence must remain isolated from SwiftTUI architecture and public API decisions.

## Pull Requests

1. Branch from `main`.
2. Complete the pull request template.
3. Run focused tests for the changed behavior.
4. Run the full macOS and Linux gate before merge.
5. Run the performance gate when runtime or rendering behavior changes.
6. Update documentation and attribution when public behavior or provenance changes.

## Code Style

- Use four-space indentation.
- Keep lines below the configured SwiftLint limits.
- Use trailing commas in multiline collections.
- Follow `.swiftlint.yml` and `.swift-format`.
