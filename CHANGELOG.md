# Changelog

All notable changes appear in this file.

## 3.0.0 - 2026-09-23

### Changed

- `PromptAutocompleteState.moveSelection(by:wrapping:)` can wrap selection at the ends; the default still clamps.
- `AgentPromptActions` collapses to a single initializer with a defaulted `diagnostic` parameter.
- `TerminalCapabilities` merges its two initializers into one; `supportsOSC52` defaults to `allowsOSC52`.
- `TerminalKeyEvent` merges its two initializers into one.
- `Runtime`'s imperative view initializer defaults `textSelectionConfiguration` to `.disabled`, and its redundant convenience initializers are removed.
- `FocusMetadata` and `HitTestMetadata` each collapse to a single initializer.
- `Image.init(_:label:background:contentMode:cellAspectRatio:id:)` moves its defaulted parameters after the required `label` and `background`.
- `AgentPrompt`'s three initializers move `actions:` directly after the document parameter, before the defaulted `configuration:`/`layoutPolicy:`.
- `ControlFocusHandler.controlFocusChanged(_:)` is renamed to `controlFocusChanged(to:)`.
- `List` is renamed to `SelectionList`.
- TermKit now requires Swift 6.4.

### Removed

- `TextRange.init(_:_:)`; use `init(lowerBound:upperBound:)`.
- `MetadataLine.visibleFields(in:)` and `text(in:)`; use `visibleFields(fittingWidth:)` and `text(fittingWidth:)`.
- `PaintContext.applyingOpacity(_:)`; use `multiplyingOpacity(_:)`.
- `Runtime.process(_: TerminalRuntimeEvent)`; use `process(terminalEvent:)`.
- `StatusPill.tone`, `StatusPillTone`, and the `tone:`-labeled initializers; use `kind`, `StatusKind`, and the `kind:`-labeled initializers.
- `VerticalEdge`; use `HorizontalEdge`.
- `MountedNode.presentationValue(for:)`; use `presentationValue(_:)`.
- `ValueAnimation.transaction(for:from:)`; use `updateValue(_:from:)`.
- `GraphemeRemap.map(_:)` and `StyleRemap.map(_:)`; use `remappedID(for:)`.
- `SelectList.setQuery(_:)`; assign `query` instead.
- `SynchronizedOutputProbe.applying(_:to:)`; use `TerminalCapabilities.applying(_:)` instead.
- `RenderStats.rebuiltInterners` and its old-label initializer parameter; use `didRebuildInterners`.
- `DiffView`; use `DiffLayout`.
- `MountedNode.preference(_:)`; use `preference(for:)`.
- `OverlayHost`'s unused `DialogHost` typealias.

### Fixed

- `Runtime.run()` waits for terminal events on a Dispatch thread, so a blocked event read does not occupy a thread of the Swift concurrency pool.

## 2.2.4 - 2026-08-15

### Fixed

- `Runtime.run()` now rejects overlapping event loops with `RuntimeError.reentrantRun`, and blocking event waits use structured `@concurrent` offloading.
- `RuntimeInvalidationChannel` retries wake delivery after an error while preserving coalesced pending invalidations.
- Releasing a view graph cancels mounted view tasks without a retain cycle.

## 2.2.3 - 2026-08-14

### Added

- `RuntimeInputInvalidation`: the runtime can request a frame after input instead of invalidating the complete frame. The `.stateDriven` policy suits an application whose input handlers mutate observable models only — a held key then repaints the cells it changed. The default `.full` keeps the 2.2 behavior, and the text selection still invalidates the complete frame.

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
