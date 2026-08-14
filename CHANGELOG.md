# Changelog

All notable changes appear in this file.

## 0.1.0 - 2026-08-14

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
