# Runtime

Understand how the runtime coordinates terminal input, frames, and cleanup.

Use one ``Runtime`` instance to own the frame loop and terminal session.

## Responsibilities

``Runtime`` coordinates reconciliation, layout, paint, cell diffs, terminal presentation, input, signals, and cleanup.

``FrameScheduler`` coalesces invalidations and supplies animation deadlines without an idle timer. ``RuntimeInvalidationChannel`` accepts requests from concurrent work.

Start the runtime from an asynchronous entry point. The runtime restores terminal state after normal exit, cancellation, signals, and errors.

Pass a declarative root ``View`` to the runtime. Use ``RuntimeView`` only when you need custom layout and paint code.

See <doc:RuntimeSetup> for a complete entry point. See <doc:TerminalFallback> for terminal capability behavior.
