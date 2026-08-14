# Changelog

All notable changes appear in this file.

## 2.2.2 - 2026-08-14

### Fixed

- A presented overlay occludes the cells it paints: a click over an overlay no longer falls through to the content beneath it. A modal overlay still blocks every click outside its own bounds.
- The bundled version integration test now follows the release version, and the release verification checks it.

## 2.2.1 - 2026-08-14

### Fixed

- A text-selection drag that returns to its anchor cell reads as a click: the release passes to the pointer dispatchers instead of ending a one-cell selection.
- The automatic copy-on-release clears the selection highlight after the clipboard write. The `.suppress` action still keeps the selection on screen.

## 2.2.0 - 2026-08-14

### Added

- Runtime overlays with z-order, modal focus, Escape dismissal, focus restoration, and timeline-driven toast expiry.
- Proposed-size geometry, flexible stack spacers, appearance hooks, and cancellable view tasks.
- Kitty base-layout keys, JCUKEN hotkey normalization, terminal titles, OSC 52 detection, and grid-aware text selection.
- Custom `SelectList` rows, static `Sparkline` charts, and semantic `StatusPill` tones with a bare presentation.

### Changed

- SGR mouse sessions now request button-motion events for text-selection drags.
- The bundled version resource and release metadata now report `2.2.0`.

## 2.1.0 - 2026-08-14

### Added

- One `TermKit` library product and module for macOS 14+ and glibc Linux.
- Declarative views, retained reconciliation, layout, animation, controls, rich text, agent interfaces, and terminal runtime.
- Bounded PNG and JPEG decoding through `swift-png` 4.5.1 and `swift-jpeg` 2.1.0.
- Truecolor, ANSI-256, ANSI-16, and monochrome terminal image rendering.
- An adaptive, silent TermKitPlayer example with original artwork and PTY tests.

### Changed

- Renamed runtime APIs to `Runtime`, `RuntimeError`, and `RuntimeDiagnostic`.
- Renamed the duration type to `TimeSpan` and the design surface to `SurfaceView`.
- Consolidated toast presentation under `ToastKind`.

### Removed

- Removed legacy targets, vendored codecs, compatibility tooling, and old module aliases.
