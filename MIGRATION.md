# Migration To TermKit 3.0.0

TermKit 3.0.0 requires Swift 6.4. Update your toolchain before you build against this release.
This is a major release: every deprecated shim from the previous release is removed. TermKit does not provide compatibility aliases.

## API Renames And Removals

| Old API | TermKit 3.0.0 |
| --- | --- |
| `TextRange.init(_:_:)` | `TextRange.init(lowerBound:upperBound:)` |
| `MetadataLine.visibleFields(in:)` | `visibleFields(fittingWidth:)` |
| `MetadataLine.text(in:)` | `text(fittingWidth:)` |
| `PaintContext.applyingOpacity(_:)` | `multiplyingOpacity(_:)` |
| `Runtime.process(_: TerminalRuntimeEvent)` | `process(terminalEvent:)` |
| `StatusPill.tone` | `StatusPill.kind` |
| `StatusPillTone` | `StatusKind` |
| `StatusPill.init(text:tone:theme:id:presentation:)` | `init(text:kind:theme:id:presentation:)` |
| `StatusPill.init(text:tone:theme:scheme:id:presentation:)` | `init(text:kind:theme:scheme:id:presentation:)` |
| `VerticalEdge` | `HorizontalEdge` |
| `MountedNode.presentationValue(for:)` | `presentationValue(_:)` |
| `ValueAnimation.transaction(for:from:)` | `updateValue(_:from:)` |
| `GraphemeRemap.map(_:)` | `remappedID(for:)` |
| `StyleRemap.map(_:)` | `remappedID(for:)` |
| `SelectList.setQuery(_:)` | assign `query` instead |
| `SynchronizedOutputProbe.applying(_:to:)` | `TerminalCapabilities.applying(_:)` |
| `RenderStats.rebuiltInterners` | `didRebuildInterners` |
| `RenderStats.init(...rebuiltInterners:)` | `init(...didRebuildInterners:)` |
| `DiffView` | `DiffLayout` |
| `MountedNode.preference(_:)` | `preference(for:)` |
| `DialogHost` | `OverlayHost` |
| `Image.init(_:id:label:contentMode:background:cellAspectRatio:)` | `Image.init(_:label:background:contentMode:cellAspectRatio:id:)` |
| `AgentPrompt` initializers (`configuration:`/`layoutPolicy:` before `actions:`) | `actions:` moves directly after the document parameter |
| `ControlFocusHandler.controlFocusChanged(_:)` | `controlFocusChanged(to:)` |
| `List` | `SelectionList` |

# Migration To TermKit 2.1.0

TermKit 2.1.0 publishes one product and one module. Replace old package products and imports with `TermKit`.

## Package Changes

Use `.product(name: "TermKit", package: "termkit")` and `import TermKit`.
Removed module imports fail by design. TermKit does not provide compatibility aliases.

## API Renames

| Old API | TermKit 2.1.0 |
| --- | --- |
| `TUIRuntime` | `Runtime` |
| `TUIRuntimeError` | `RuntimeError` |
| `TUIRuntimeDiagnostic` | `RuntimeDiagnostic` |
| `TUIDuration` | `TimeSpan` |
| Design `Surface` | `SurfaceView` |
| Separate toast enums | `ToastKind` |
| `SWIFTTUI_*` variables | `TERMKIT_*` variables |

The renderer type remains `Surface`.

The migration removes the internal showcase catalog types `ShowcaseCatalog`, `ShowcaseComponent`,
and `ShowcaseEntry`. Use the standalone `Examples/TermKitPlayer` package for example content.

## Architecture Changes

TermKit uses one module with subsystem directories. Applications should not depend on former module boundaries.
The runtime owns the terminal lifecycle, retained graph, frame scheduler, and cleanup.

TUIkit 1.x view code requires a new declarative boundary based on `View`, `NodeDescriptor`, and `graphBody`.
Networking, persistence, tool execution, and application data remain application responsibilities.
