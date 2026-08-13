# Architecture

SwiftTUI separates platform I/O, rendering, graph state, layout, animation, controls, and application-specific components.

## Frame Pipeline

1. A state or input event invalidates structure, layout, paint, or a terminal region.
2. `FrameScheduler` coalesces requests and supplies one monotonic frame tick.
3. `ViewGraph` reconciles descriptors when structure is dirty.
4. The runtime measures and places the affected branches when layout is dirty.
5. Views paint direct cells or bounded isolated layers into the root `Surface`.
6. `DamageTracker` limits the front/back diff to affected rows and ranges.
7. `ANSIEncoder` encodes changed runs and tracks cursor and SGR state.
8. `TerminalSession` performs one logical buffered write.
9. The graph commits lifecycle and animation effects only after successful presentation.

Paint-only frames skip body evaluation, reconciliation, and layout. Ordinary content paints without an offscreen layer. Opacity and transitions use bounded layers.

If a frame fails, the runtime restores graph, animation, geometry, raster, and dirty-state snapshots. The runtime then restores terminal state.

## Concurrency

View operations, graph mutation, layout, paint, and presentation run on `@MainActor`. Blocking terminal waits run in a detached task. `TerminalEventSource` uses a self-pipe to wake the runtime for input, signals, and external invalidation.

Signal handlers only set pending bits and write to the self-pipe. Session cleanup runs in ordinary runtime code.

## Rendering

A packed cell contains a grapheme identifier, style identifier, display width, and flags. Stable session interners make equality an integer comparison. When an interner reaches its configured threshold, the presenter rebuilds it from live surfaces and forces one repaint.

Wide graphemes reserve continuation cells. Surface writes, clipping, clearing, composition, and diffing preserve the complete grapheme atom.

## Animation

`withAnimation` places a `Transaction` in task-local storage. Animation tracks retain floating-point presentation values and sample current time. `FrameScheduler` caps cadence at 60 FPS, drops stale demand, and clamps large frame deltas.

`MotionEnvironmentValues` controls animation enablement and reduced motion. Indefinite components expose static fallbacks.

## Agent UI

`TUIAgentUI` contains generic models and semantic renderers. It does not execute tools, call model providers, or own session persistence. Rich content delegates to `TUIRichText`; selection and focus semantics delegate to general controls.
