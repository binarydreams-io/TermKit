# Architecture

Explore the components that process a TermKit frame from state to terminal output.

TermKit separates view state, layout, rendering, and terminal I/O within one module.

## Frame pipeline

For each structural update, the view graph prepares and stages a reconciliation plan. Layout then measures and places the mounted nodes.

The renderer paints packed cells into a ``Surface``. Damage tracking limits the cell diff, and ``ANSIEncoder`` encodes changed runs.

The runtime finishes graph lifecycle work only after successful terminal presentation. If a frame fails, it rolls back staged graph changes and restores terminal state.

## Execution

View evaluation, graph mutation, layout, paint, and presentation run on the main actor. ``TerminalEventSource`` wakes the runtime for input and signals.

``RuntimeInvalidationChannel`` lets concurrent work request another frame safely.

See <doc:RuntimeArchitecture> for runtime ownership and scheduling.
