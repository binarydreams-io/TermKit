# Migration

Move applications from TUIkit 1.x to SwiftTUI.

## Package And Imports

Replace the `TUIkit` product and module with `SwiftTUI`. SwiftTUI does not preserve TUIkit 1.x source or binary compatibility.

## Application Changes

Rewrite the application at the view boundary. Use the SwiftTUI view graph, layout, renderer, controls, and runtime APIs instead of legacy scenes, frame buffers, and render-cache identity.

Replace component timers with transactions, animation tracks, or ``TimelineView``. Use ``TUIRuntime`` to own the terminal lifecycle.
