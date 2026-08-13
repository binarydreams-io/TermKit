//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyBinding.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Binding

/// A declared key binding: a shortcut, its label, and where it belongs in
/// the footer and the `?` cheat sheet.
///
/// Declaring a binding is display-only — it does not attach a key handler.
/// Pair it with `onKeyPress` or a focus handler that reacts to the same
/// shortcut.
///
/// # Example
///
/// ```swift
/// Text("Analyze")
///     .keyBinding("a", "Analyze", group: "Project")
///     .onKeyPress(.character("a")) { analyze() }
/// ```
public struct KeyBinding: Equatable, Sendable, Identifiable {
  /// The shortcut text shown to the user, e.g. `"a"`, `"esc"`, `"↑↓"`.
  public let shortcut: String

  /// The action label, e.g. `"Analyze"`.
  public let label: String

  /// The cheat-sheet group, usually the screen name.
  public let group: String

  /// The footer priority; lower renders first.
  public let order: Int

  /// The key that triggers this binding, derived from `shortcut`.
  ///
  /// Uses the same derivation table as `StatusBarItem` (`keyFromShortcutText`
  /// in `Shortcut+KeyMapping.swift`), so a `Shortcut.*` symbol and its word
  /// spelling always agree: e.g. both `"esc"` and `Shortcut.escape` ("⎋")
  /// map to `.escape`, both `Shortcut.arrowUp` ("↑") and `"tab"`/`"enter"`/
  /// `"space"` map to their named keys. A single character not covered by
  /// that table maps to `.character`. Anything else (multi-character
  /// shortcuts like `"↑↓"`) has no derived key.
  public let triggerKey: Key?

  /// A stable identifier combining group, shortcut, and label.
  public var id: String { "\(group)|\(shortcut)|\(label)" }

  /// Creates a key binding, deriving `triggerKey` from `shortcut`.
  ///
  /// - Parameters:
  ///   - shortcut: The shortcut text shown to the user.
  ///   - label: The action label.
  ///   - group: The cheat-sheet group (default: `""`).
  ///   - order: The footer priority; lower renders first (default: `0`).
  public init(shortcut: String, label: String, group: String = "", order: Int = 0) {
    self.shortcut = shortcut
    self.label = label
    self.group = group
    self.order = order
    self.triggerKey = keyFromShortcutText(shortcut)
  }
}

// MARK: - Key Bindings Preference

/// A preference key collecting declared key bindings up the view hierarchy
/// in tree order.
public struct KeyBindingsKey: PreferenceKey {
  public static let defaultValue: [KeyBinding] = []

  public static func reduce(value: inout [KeyBinding], nextValue: () -> [KeyBinding]) {
    value.append(contentsOf: nextValue())
  }
}

// MARK: - Key Binding Modifier

extension View {
  /// Declares a key binding for the footer and the `?` cheat sheet.
  ///
  /// This is declaration only: it registers the shortcut, label, group, and
  /// order as a preference. It does not attach a key handler — pair it with
  /// `onKeyPress` or a focus handler that reacts to the same shortcut.
  ///
  /// - Parameters:
  ///   - shortcut: The shortcut text shown to the user, e.g. `"a"`, `"esc"`.
  ///   - label: The action label, e.g. `"Analyze"`.
  ///   - group: The cheat-sheet group, usually the screen name (default: `""`).
  ///   - order: The footer priority; lower renders first (default: `0`).
  /// - Returns: A view that declares the key binding as a preference.
  public func keyBinding(_ shortcut: String, _ label: String, group: String = "", order: Int = 0) -> some View {
    preference(
      key: KeyBindingsKey.self,
      value: [KeyBinding(shortcut: shortcut, label: label, group: group, order: order)]
    )
  }
}
