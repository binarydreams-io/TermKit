//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBar.swift
//
//  Created by LAYERED.work
//  License: MIT  Always rendered at the bottom of the terminal, never dimmed by overlays.
//

// MARK: - StatusBar View

/// A status bar that displays at the bottom of the terminal.
///
/// The status bar shows keyboard shortcuts and their descriptions.
/// It's rendered separately from the main view tree and is never
/// affected by overlays or dimming.
///
/// # Layout
///
/// The status bar consists of two containers:
/// - **User Container** (left): User-defined items, sorted by order
/// - **System Container** (right): System items (quit, help, theme), fixed order
///
/// ```
/// ┌────────────────────────────────────────┬───────────────────────────────┐
/// │ s save   x action   ↑↓ nav             │ q quit   ? help   t theme    │
/// └────────────────────────────────────────┴───────────────────────────────┘
/// ```
///
/// # Usage
///
/// To set status bar items, use the environment:
///
/// ```swift
/// // In renderToBuffer(context:):
/// let statusBar = context.environment.statusBar
/// statusBar.setItems([
///     StatusBarItem(shortcut: "s", label: "save"),
///     StatusBarItem(shortcut: "↑↓", label: "nav"),
/// ])
/// ```
public struct StatusBar: View {
  /// User items (left container).
  public let userItems: [any StatusBarItemProtocol]

  /// System items (right container).
  public let systemItems: [any StatusBarItemProtocol]

  /// The visual style.
  public let style: StatusBarStyle

  /// The horizontal alignment of user items within the left container.
  public let alignment: StatusBarAlignment

  /// The highlight color for shortcut keys.
  public let highlightColor: Color

  /// The label color.
  public let labelColor: Color?

  /// Creates a status bar with separate user and system items.
  ///
  /// - Parameters:
  ///   - userItems: User-defined items (left container).
  ///   - systemItems: System items (right container).
  ///   - style: The visual style (default: `.compact`).
  ///   - alignment: The alignment of user items (default: `.leading`).
  ///   - highlightColor: The color for shortcut keys (default: `.cyan`).
  ///   - labelColor: The color for labels (default: nil, terminal default).
  public init(
    userItems: [any StatusBarItemProtocol] = [],
    systemItems: [any StatusBarItemProtocol] = [],
    style: StatusBarStyle = .compact,
    alignment: StatusBarAlignment = .leading,
    highlightColor: Color = .cyan,
    labelColor: Color? = nil
  ) {
    self.userItems = userItems
    self.systemItems = systemItems
    self.style = style
    self.alignment = alignment
    self.highlightColor = highlightColor
    self.labelColor = labelColor
  }

  /// Creates a status bar with all items combined (legacy compatibility).
  ///
  /// - Parameters:
  ///   - items: All items to display (will be treated as user items).
  ///   - style: The visual style (default: `.compact`).
  ///   - alignment: The horizontal alignment (default: `.justified`).
  ///   - highlightColor: The color for shortcut keys (default: `.cyan`).
  ///   - labelColor: The color for labels (default: nil, terminal default).
  public init(
    items: [any StatusBarItemProtocol],
    style: StatusBarStyle = .compact,
    alignment: StatusBarAlignment = .justified,
    highlightColor: Color = .cyan,
    labelColor: Color? = nil
  ) {
    self.userItems = items
    self.systemItems = []
    self.style = style
    self.alignment = alignment
    self.highlightColor = highlightColor
    self.labelColor = labelColor
  }

  /// Creates a status bar using a builder.
  ///
  /// - Parameters:
  ///   - style: The visual style.
  ///   - alignment: The horizontal alignment.
  ///   - highlightColor: The color for shortcut keys.
  ///   - labelColor: The color for labels.
  ///   - builder: A closure that returns items.
  public init(
    style: StatusBarStyle = .compact,
    alignment: StatusBarAlignment = .justified,
    highlightColor: Color = .cyan,
    labelColor: Color? = nil,
    @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
  ) {
    self.userItems = builder()
    self.systemItems = []
    self.style = style
    self.alignment = alignment
    self.highlightColor = highlightColor
    self.labelColor = labelColor
  }

  /// All items combined (sorted user items, then filtered system items).
  ///
  /// User items are sorted by their `order` property.
  /// System items maintain their fixed order (quit, help, theme).
  /// User items override system items with the same shortcut.
  /// Use this for event handling to check all items.
  public var allItems: [any StatusBarItemProtocol] {
    let userShortcuts = Set(userItems.map(\.shortcut))
    let filteredSystemItems = systemItems.filter { !userShortcuts.contains($0.shortcut) }
    return userItems.sorted { $0.order < $1.order } + filteredSystemItems
  }

  /// Whether the status bar has any items to display.
  public var hasItems: Bool {
    !userItems.isEmpty || !systemItems.isEmpty
  }
}

// MARK: - Status Bar Height Helper

extension StatusBar {
  /// The height of the status bar in lines.
  public var height: Int {
    switch style {
    case .compact:
      1
    case .bordered:
      3
    }
  }
}
