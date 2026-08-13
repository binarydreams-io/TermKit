//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalTitleModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Terminal Title Preference

/// A preference key carrying the terminal window title up the view hierarchy.
///
/// `reduce` keeps the last declared non-nil title, so a nested screen
/// overrides the title of the container that presents it, and a subtree
/// that declares nothing leaves the enclosing title untouched.
public struct TerminalTitleKey: PreferenceKey {
  /// No declared title.
  public static let defaultValue: String? = nil

  public static func reduce(value: inout String?, nextValue: () -> String?) {
    if let next = nextValue() {
      value = next
    }
  }
}

// MARK: - Terminal Title Modifier

extension View {
  /// Sets the terminal window title while this view is on screen.
  ///
  /// The runtime writes the title once per change, saves the previous
  /// title at startup, and restores it on exit.
  ///
  /// # Example
  ///
  /// ```swift
  /// ProjectList()
  ///     .terminalTitle("Rig — Projects")
  /// ```
  ///
  /// - Parameter title: The window title text.
  /// - Returns: A view that declares the window title as a preference.
  public func terminalTitle(_ title: String) -> some View {
    preference(key: TerminalTitleKey.self, value: title)
  }
}
