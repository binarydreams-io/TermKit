//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoop+Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A snapshot of environment values that affect rendered output.
///
/// Used by `RenderLoop` to detect environment changes (theme, appearance)
/// between frames. When the snapshot differs from the previous frame, the
/// render cache is cleared so `EquatableView`-cached subtrees re-render
/// with the updated values.
///
/// Only tracks values that affect visual output — reference-type infrastructure
/// services (`FocusManager`, `ThemeManager`) are excluded.
private struct EnvironmentSnapshot: Equatable {
  /// The active palette identifier.
  let paletteID: String

  /// The active appearance identifier.
  let appearanceID: String

  /// Creates a snapshot from fully-built environment values.
  init(from environment: EnvironmentValues) {
    self.paletteID = environment.palette.id
    self.appearanceID = environment.appearance.id
  }
}

@MainActor
struct RenderEnvironmentTracker {
  private var lastSnapshot: EnvironmentSnapshot?

  /// Clears the render cache when environment values affecting visual output changed.
  ///
  /// Compares the current palette and appearance identifiers with the previous
  /// frame's snapshot. On mismatch, all `EquatableView`-cached subtrees are
  /// invalidated so they re-render with the new theme/appearance.
  ///
  /// This runs once per frame (two string comparisons) and ensures
  /// developers never need to manually invalidate the cache after theme changes.
  mutating func invalidateCacheIfChanged(environment: EnvironmentValues, tuiContext: TUIContext) {
    let currentSnapshot = EnvironmentSnapshot(from: environment)
    if let lastSnapshot, lastSnapshot != currentSnapshot {
      tuiContext.renderCache.clearAll()
    }
    lastSnapshot = currentSnapshot
  }
}
