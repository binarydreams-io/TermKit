# Architecture

Understand how SwiftTUI separates view state, layout, rendering, and terminal I/O.

## Frame Pipeline

The view graph stages each reconciliation before layout and paint. The renderer writes packed cells to a surface, limits the diff to damaged regions, and encodes changed runs as ANSI output.

The runtime commits lifecycle effects only after successful terminal presentation. If a frame fails, the graph rolls back the staged commit and the runtime restores terminal state.

## Execution

View operations, graph mutation, layout, paint, and presentation run on the main actor. Terminal event sources wake the runtime for input, signals, and external invalidation.

See <doc:Runtime> for runtime ownership and scheduling.
