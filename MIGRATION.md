# Migration To TermKit 0.1.0

TermKit 0.1.0 publishes one product and one module. Replace old package products and imports with `TermKit`.

## Package Changes

Use `.product(name: "TermKit", package: "termkit")` and `import TermKit`.
Removed module imports fail by design. TermKit does not provide compatibility aliases.

## API Renames

| Old API | TermKit 0.1.0 |
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
