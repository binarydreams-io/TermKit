//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SelectionModeState.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

// MARK: - Selection Mode State

/// Whether the terminal, not the application, owns the mouse.
///
/// An application that captures the mouse receives clicks and wheel
/// events, but the user can no longer select text with a drag. Selection
/// mode releases the capture for as long as it stays active, which makes
/// the terminal's own selection and copy work again.
///
/// The runtime owns one instance and applies every change after input
/// handling. Read it from the environment:
///
/// ```swift
/// @Environment(\.selectionMode) private var selectionMode
///
/// Button("Select text") { selectionMode.isActive.toggle() }
/// ```
@Observable
public final class SelectionModeState {
  /// Whether the terminal currently owns the mouse.
  public var isActive: Bool = false

  /// Creates state with selection mode inactive.
  public init() {}
}

// MARK: - Environment Key

/// Environment key for the selection mode state.
private struct SelectionModeKey: EnvironmentKey {
  static var defaultValue: SelectionModeState { SelectionModeState() }
}

extension EnvironmentValues {
  /// Whether the terminal owns the mouse instead of the application.
  ///
  /// Outside a running application this resolves to a detached instance,
  /// so reading it never fails and changing it has no terminal effect.
  public var selectionMode: SelectionModeState {
    get { self[SelectionModeKey.self] }
    set { self[SelectionModeKey.self] = newValue }
  }
}
