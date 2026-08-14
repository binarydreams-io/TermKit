# Subsystem Directories

Find the source directory that owns each TermKit subsystem.

TermKit exposes one module. Source directories group related implementation and API files.

## Directory map

- `Foundation` contains geometry, color, time, packed cells, and interners.
- `Terminal` contains sessions, input parsing, capabilities, signals, and transport.
- `Rendering` contains surfaces, damage tracking, cell diffs, and ANSI encoding.
- `ViewGraph` contains views, state, environment values, preferences, and reconciliation.
- `Layout` contains measurement, placement, stacks, frames, padding, and scrolling.
- `Animation` contains transactions, tracks, transitions, schedules, and timelines.
- `Controls` contains controls, focus, commands, overlays, and semantics.
- `Design` contains semantic themes and presentation primitives.
- `RichText` contains Markdown, code, syntax highlighting, and unified diffs.
- `AgentUI` contains reusable models and components for agent applications.
- `Runtime` contains the frame loop, invalidation channel, and frame presenter.
- `Image` contains bounded PNG and JPEG decoding, raster pixels, and terminal image rendering.

All public symbols use `import TermKit` regardless of their source directory.
