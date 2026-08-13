//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarItem+Implementation.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Status Bar Item

/// A status bar item displaying a shortcut and its description.
///
/// # Example
///
/// ```swift
/// StatusBarItem(shortcut: "q", label: "quit") {
///     app.quit()
/// }
///
/// StatusBarItem(shortcut: "↑↓", label: "nav", key: .up) // Info only, no action
///
/// // With custom order
/// StatusBarItem(shortcut: "s", label: "save", order: .early) {
///     save()
/// }
/// ```
public struct StatusBarItem: StatusBarItemProtocol, Identifiable, @unchecked Sendable {
  /// The unique identifier for this item.
  public let id: String

  /// The shortcut key(s) displayed to the user (e.g. `"q"`, `"↑↓"`).
  public let shortcut: String

  /// The descriptive label shown next to the shortcut (e.g. `"quit"`, `"nav"`).
  public let label: String

  /// The key that triggers this item's action, or `nil` for informational items.
  public let triggerKey: Key?

  /// The sort order controlling horizontal position in the status bar.
  public let order: StatusBarItemOrder

  /// The action to perform when the shortcut is triggered.
  private let action: (() -> Void)?

  /// Creates a status bar item with an action.
  ///
  /// - Parameters:
  ///   - shortcut: The shortcut key(s) to display.
  ///   - label: A short description (one word).
  ///   - key: The key that triggers the action (derived from shortcut if not provided).
  ///   - order: The display order (default: `.default`).
  ///   - action: The action to perform.
  public init(
    shortcut: String,
    label: String,
    key: Key? = nil,
    order: StatusBarItemOrder = .default,
    action: (() -> Void)? = nil
  ) {
    self.id = "\(shortcut)-\(label)"
    self.shortcut = shortcut
    self.label = label
    self.order = order
    self.action = action

    // Derive trigger key from shortcut if not explicitly provided.
    self.triggerKey = key ?? keyFromShortcutText(shortcut)
  }

  /// Creates an informational status bar item (no action).
  ///
  /// - Parameters:
  ///   - shortcut: The shortcut key(s) to display.
  ///   - label: A short description.
  ///   - order: The display order (default: `.default`).
  public init(shortcut: String, label: String, order: StatusBarItemOrder = .default) {
    self.init(shortcut: shortcut, label: label, key: nil, order: order, action: nil)
  }

  /// Whether this item has an action to execute.
  public var hasAction: Bool {
    action != nil
  }
}

// MARK: - Public API

extension StatusBarItem {
  /// Executes the item's action.
  public func execute() {
    action?()
  }

  /// Override matching for special cases.
  public func matches(_ event: KeyEvent) -> Bool {
    // Handle arrow key combinations like "↑↓"
    if shortcut.contains("↑"), event.key == .up {
      return true
    }
    if shortcut.contains("↓"), event.key == .down {
      return true
    }
    if shortcut.contains("←"), event.key == .left {
      return true
    }
    if shortcut.contains("→"), event.key == .right {
      return true
    }

    // Standard matching
    guard let trigger = triggerKey else { return false }

    // For character keys, do case-sensitive matching
    // "n" only matches 'n', "N" only matches 'N' (Shift+n)
    if case let .character(triggerChar) = trigger,
       case let .character(eventChar) = event.key
    {
      return triggerChar == eventChar
    }

    return event.key == trigger
  }
}
