# Runtime

Use one runtime to own the frame loop and terminal session.

## Responsibilities

``TUIRuntime`` coordinates reconciliation, layout, paint, diff generation, terminal presentation, input, signals, and cleanup. ``FrameScheduler`` coalesces invalidations and supplies animation deadlines without an idle timer.

Applications start the runtime from an asynchronous entry point. The runtime restores terminal state after normal exit, cancellation, signals, and errors.

Pass a declarative root view to ``TUIRuntime``. The ``RuntimeView`` protocol is an escape hatch for custom layout and paint code.

See <doc:RuntimeSetup> for a complete entry point. See <doc:TerminalFallback> for terminal capability behavior.
