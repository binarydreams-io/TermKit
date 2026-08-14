# Migration

Update an application to use the current TermKit product and APIs.

TermKit 0.1.0 uses one `TermKit` library product and one `TermKit` module.

## Historical context

Earlier development versions split the package into several modules and used different product names. Those interfaces are not part of TermKit 0.1.0.

When you update an application from an earlier version, depend on the `TermKit` product and use `import TermKit`.

Use ``View`` for declarative content and ``Runtime`` for the terminal lifecycle. Use ``RuntimeView`` only when you need custom layout and paint code.

Replace component timers with ``withAnimation(_:completion:_:)``, value animations, or ``TimelineView``.

Rename `TUIRuntime` to ``Runtime`` and `TUIDuration` to ``TimeSpan``.
Use ``SurfaceView`` for the design primitive. The renderer continues to use ``Surface``.
Rename old environment variables to the `TERMKIT_*` form.

TermKit does not provide aliases for removed modules or API names.
