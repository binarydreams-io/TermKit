# Modules

Choose the framework layer that owns each responsibility.

## Public Modules

- `TUIFoundation` defines geometry, color, time, packed cells, and interning.
- `TUITerminal` owns terminal sessions, input, capabilities, signals, and transport.
- `TUIRenderer` owns surfaces, damage tracking, diffs, and ANSI encoding.
- `TUIViewGraph` defines views, state, environment, preferences, and reconciliation.
- `TUILayout` measures and places views.
- `TUIAnimation` provides transactions, tracks, transitions, and timelines.
- `TUIControls` provides controls, focus, commands, and semantics.
- `TUIDesign` provides semantic themes and presentation primitives.
- `TUIRichText` renders Markdown, code, syntax highlighting, and unified diffs.
- `TUIAgentUI` provides generic coding-agent components and models.
- `TUIRuntime` owns the frame loop and terminal presenter.
- `SwiftTUI` reexports the public modules as one package interface.
