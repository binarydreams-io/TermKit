# SwiftTUI

SwiftTUI is a Swift terminal UI framework for macOS and Linux. It uses a declarative view API, a retained view graph, packed terminal cells, damage-limited output, and one shared animation scheduler.

The current package version is `0.1.0-preview`. Its public API can change before version 1.0.

SwiftTUI derives from TUIkit and adapts interaction patterns from OpenCode. It is a new project and does not preserve TUIkit 1.x source or binary compatibility. See [CREDITS.md](CREDITS.md) and [NOTICE.md](NOTICE.md).

## Requirements

- Swift 6.0 or later
- macOS 14 or later
- A glibc-based Linux distribution
- A UTF-8 terminal

Ghostty is the reference terminal. Kitty, WezTerm, iTerm2, and modern xterm-compatible terminals use the same cell-diff fallback path.

## Package Setup

Add the package URL and the `SwiftTUI` product to your `Package.swift`:

```swift
let package = Package(
    name: "YourApp",
    dependencies: [
        .package(url: "<repository-url>", exact: "0.1.0-preview")
    ],
    targets: [
        .executableTarget(
            name: "YourApp",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ]
        )
    ]
)
```

Import the umbrella module:

```swift
import SwiftTUI
```

The umbrella module exports the foundation, terminal, renderer, graph, layout, animation, controls, design, rich-text, agent UI, and runtime modules.

## Public Model

Applications declare view values with `View` and `ViewBuilder`. The runtime reconciles these values into a retained `ViewGraph`.

```swift
import SwiftTUI

struct CounterView: View {
    @State private var count = 0

    var graphBody: [NodeDescriptor] {
        VStack(alignment: .leading, spacing: 1) {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
        .padding(1)
        .graphBody
    }
}
```

Pass the root view to `TUIRuntime`. The runtime owns reconciliation, incremental layout and paint, terminal presentation, input, signals, and cleanup. `TimelineView` and animation tracks request frames from one `FrameScheduler`. An idle runtime has no frame deadline.

See the [runtime setup guide](Sources/SwiftTUI/SwiftTUI.docc/RuntimeSetup.md) for a complete asynchronous entry point. Implement `RuntimeView` only when the application needs a low-level custom layout and paint pipeline.

## Showcase

Run the component showcase in a terminal:

```bash
swift run SwiftTUIShowcase
```

Press `q` or `Esc` to exit. The showcase renders real prompt, command palette, message, reasoning, tool, diff, permission, question, toast, and sidebar models.

## Modules

| Module | Responsibility |
| --- | --- |
| `TUIFoundation` | Geometry, color, time, packed cells, interning |
| `TUITerminal` | POSIX session, input, capabilities, signals, transport |
| `TUIRenderer` | Surfaces, painting, damage, diff, ANSI encoding |
| `TUIViewGraph` | Views, state, environment, preferences, reconciliation |
| `TUILayout` | Measure, place, stacks, lazy layout, scrolling |
| `TUIAnimation` | Transactions, tracks, transitions, timelines |
| `TUIControls` | Generic controls, focus, commands, semantics |
| `TUIDesign` | Semantic themes and presentation primitives |
| `TUIRichText` | Markdown, code, syntax highlighting, unified diff |
| `TUIAgentUI` | Generic coding-agent components and models |
| `TUIRuntime` | Frame loop and terminal presenter |
| `SwiftTUI` | Public umbrella module |

See [docs/architecture.md](docs/architecture.md) for the runtime pipeline.
See [docs/development-stages.md](docs/development-stages.md) for evidence from the 12 implementation stages.

## Verification

Run focused package tests:

```bash
swift test
```

Run the release performance gates:

```bash
./scripts/swifttui-benchmark.sh
```

The benchmark runner fails if SwiftPM does not discover the performance tests. Accepted reference results are in [docs/benchmarks.md](docs/benchmarks.md).

## Compatibility

SwiftTUI probes synchronized output. A failed optional probe disables only that optimization. The renderer continues with ordinary ANSI presentation and one buffered logical write.

See these documents before a preview upgrade or production evaluation:

- [MIGRATION.md](MIGRATION.md)
- [LIMITATIONS.md](LIMITATIONS.md)
- [docs/terminal-compatibility.md](docs/terminal-compatibility.md)

## License

SwiftTUI is available under the MIT License. The repository retains the complete TUIkit and OpenCode notices in [NOTICE.md](NOTICE.md).
