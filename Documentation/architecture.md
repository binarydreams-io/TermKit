# Architecture

TermKit publishes one Swift module. Subsystem directories define review boundaries without creating module dependencies.

## Frame Pipeline

1. `TerminalEventSource` reports input, wake, resize, and signal events.
2. `Runtime` updates state and records invalidation.
3. `ViewGraph` expands declarative views and reconciles retained nodes.
4. Layout measures and places dirty nodes.
5. Renderers paint packed cells and semantic nodes into a `Surface`.
6. `CellDiff` limits output to changed cells and valid damage regions.
7. `ANSIEncoder` emits one logical presentation write.

The graph commit finishes only after presentation succeeds. A frame failure rolls back graph state and restores the terminal session.

## Concurrency

View expansion, mutable graph state, control actions, and runtime transitions run on the main actor.
Concurrent producers send bounded invalidation through `RuntimeInvalidationChannel`.

## Scheduling

One `FrameScheduler` combines explicit invalidation, animation cadence, and timeline deadlines.
Static views do not request idle frames. Reduced motion resolves animated presentation to a static state.

## Images

The image wrapper performs bounded reads, signature checks, metadata inspection, and checked allocation arithmetic.
Upstream PNG and JPEG codecs return straight RGBA8 pixels. `Image` samples those pixels into half-block terminal cells.

## Application Boundary

TermKit owns terminal UI behavior. Applications own networking, persistence, business logic, tool execution, and audio.
