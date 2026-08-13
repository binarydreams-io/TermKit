//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarItem.swift
//
//  Created by LAYERED.work
//  License: MIT  style, shortcut symbols, and system items.
//

// MARK: - Status Bar Style

/// The visual style of the status bar.
public enum StatusBarStyle: Sendable {
  /// A single line with horizontal padding.
  case compact

  /// Bordered with the current appearance's border style.
  case bordered
}

// MARK: - Status Bar Alignment

/// The horizontal alignment of items within the status bar.
public enum StatusBarAlignment: Sendable {
  /// Items are aligned to the left (leading edge).
  case leading

  /// Items are aligned to the right (trailing edge).
  case trailing

  /// Items are centered horizontally.
  case center

  /// Items are evenly distributed across the full width.
  case justified
}

// MARK: - Status Bar Item Order

/// Defines the display order of status bar items.
///
/// Items are sorted by their order value (ascending). Lower values appear first (left).
/// System items appear on the right side with high order values.
///
/// # Order Ranges
///
/// - `0-99`: Reserved for leading items
/// - `100-899`: User-defined items (default: 500)
/// - `900-999`: Reserved for system items (quit, help, theme) on the right
///
/// # System Item Layout (from right edge)
///
/// ```
/// [user items...] [q quit] [? help] [t theme]
/// ```
///
/// # Example
///
/// ```swift
/// // Custom item appears on the left (before system items)
/// StatusBarItem(shortcut: "s", label: "save", order: .default)
/// ```
public struct StatusBarItemOrder: Comparable, Sendable {
  /// The numeric sort value (lower values appear first).
  public let value: Int

  /// Creates a status bar item order with the given sort value.
  ///
  /// - Parameter value: The numeric sort value.
  public init(_ value: Int) {
    self.value = value
  }

  /// Compares two orders by their numeric value.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.value < rhs.value
  }

  // MARK: - User Item Orders

  /// Default order for user-defined items (appears on the left).
  public static let `default` = Self(500)

  /// Order for items that should appear early (leftmost user items).
  public static let early = Self(100)

  /// Order for items that should appear late (rightmost user items, before system items).
  public static let late = Self(800)

  // MARK: - System Item Orders (right side)

  /// Order for the quit item (leftmost of system items).
  /// Appears as: `[...user items] [q quit] [a appearance] [t theme]`
  public static let quit = Self(900)

  /// Order for the appearance item (middle system item).
  public static let appearance = Self(910)

  /// Order for the theme item (rightmost).
  public static let theme = Self(920)
}

// MARK: - Status Bar Item Protocol

/// A protocol for items that can be displayed in a status bar.
///
/// Implement this protocol to create custom status bar items.
/// The default `StatusBarItem` already conforms to this protocol.
public protocol StatusBarItemProtocol: Sendable {
  /// The unique identifier for this item.
  var id: String { get }

  /// The shortcut key(s) to display (e.g., "q", "↑↓", "⎋").
  var shortcut: String { get }

  /// A short description (one word, e.g., "quit", "nav", "close").
  var label: String { get }

  /// The key event that triggers this item's action.
  ///
  /// Return nil if the item is purely informational (no action).
  var triggerKey: Key? { get }

  /// The display order of this item.
  ///
  /// Items are sorted by order (ascending). Lower values appear first.
  var order: StatusBarItemOrder { get }

  /// Whether this item matches a given key event.
  ///
  /// Override this for complex matching (e.g., arrow keys).
  func matches(_ event: KeyEvent) -> Bool
}

/// Default implementations
extension StatusBarItemProtocol {
  /// Default order for user-defined items.
  public var order: StatusBarItemOrder {
    .default
  }

  /// Whether this item's trigger key matches the given key event.
  ///
  /// Returns `false` if the item has no trigger key (informational only).
  ///
  /// - Parameter event: The key event to match against.
  /// - Returns: `true` if the event matches this item's trigger key.
  public func matches(_ event: KeyEvent) -> Bool {
    guard let trigger = triggerKey else { return false }
    return event.key == trigger
  }
}
