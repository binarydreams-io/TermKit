# Migrating From TUIkit 1.x

SwiftTUI does not preserve TUIkit 1.x source or binary compatibility. Treat the migration as an application rewrite at the view boundary.

## Release 0.1.0-preview

This section applies to version `0.1.0-preview`.

## Package Product

Replace the `TUIkit` product with `SwiftTUI`:

```swift
.product(name: "SwiftTUI", package: "SwiftTUI")
```

Replace `import TUIkit` with `import SwiftTUI`.

## Application Lifecycle

TUIkit 1.x applications use `App`, `Scene`, and `WindowGroup`. SwiftTUI applications create a `TerminalSession`, `FramePresenter`, terminal event source, and `TUIRuntime`. Pass the root `View` to `TUIRuntime`.

Use `TUIRuntime.run()` from an async `@main` entry point. The runtime owns terminal cleanup for normal exit, errors, cancellation, and signals.

Implement `RuntimeView` only for a low-level custom layout and paint pipeline. Most applications use `TUIRuntime(view: View, ...)`.

## Rendering

Do not return ANSI strings or legacy frame buffers. Paint into `TUIRenderer.Surface` with interned grapheme and style identifiers.

Report local damage with `DamageTracker`. The presenter compares the completed surface with the previous surface and writes changed cells.

## State And Views

Use the `TUIViewGraph` `View`, `ViewBuilder`, `State`, `Environment`, and preference APIs. Structural identity and explicit keys determine state retention.

Do not depend on TUIkit 1.x render-cache identity. SwiftTUI commits lifecycle effects only after a successful frame.

## Layout

Replace legacy string-width layout with `TUILayout` proposals, measurement, and placement. Use `LazyLayoutPlanner` or `ConversationViewport` for large transcripts.

## Animation

Replace private component timers with `Transaction`, `withAnimation`, animation tracks, or `TimelineView`. The runtime scheduler caps active animation demand at 60 FPS and has no idle timer.

## Controls And Agent UI

Use `TUIControls` for general controls. Use `TUIAgentUI` only for generic coding-agent presentation models. Application networking, persistence, and tool execution remain outside the framework.

## Preview Changes

Version 0.x releases can change public APIs. Record each future breaking change in this file before publishing the release.
