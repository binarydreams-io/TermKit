//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Menu.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A menu item representing a single selectable option.
public struct MenuItem: Identifiable {
  /// The unique identifier.
  public let id: String

  /// The display label.
  public let label: String

  /// An optional keyboard shortcut (e.g., "1", "a", "q").
  public let shortcut: Character?

  /// Creates a menu item.
  ///
  /// - Parameters:
  ///   - id: The unique identifier (defaults to label).
  ///   - label: The display label.
  ///   - shortcut: An optional keyboard shortcut character.
  public init(id: String? = nil, label: String, shortcut: Character? = nil) {
    self.id = id ?? label
    self.label = label
    self.shortcut = shortcut
  }
}

/// A vertical menu displaying a list of selectable items.
///
/// `Menu` renders items as a vertical list with optional shortcuts.
/// The currently selected item is highlighted.
///
/// # Basic Example (Static)
///
/// ```swift
/// Menu(
///     title: "Main Menu",
///     items: [
///         MenuItem(label: "Text Styles", shortcut: "1"),
///         MenuItem(label: "Colors", shortcut: "2"),
///         MenuItem(label: "Quit", shortcut: "q")
///     ],
///     selectedIndex: 0
/// )
/// ```
///
/// # Interactive Example (with Binding)
///
/// ```swift
/// struct ContentView: View {
///     @State var selection = 0
///
///     var body: some View {
///         Menu(
///             title: "Main Menu",
///             items: menuItems,
///             selection: $selection,
///             onSelect: { index in
///                 handleSelection(index)
///             }
///         )
///     }
/// }
/// ```
public struct Menu: View {
  /// The menu title (optional).
  let title: String?

  /// The menu items.
  let items: [MenuItem]

  /// The currently selected item index.
  var selectedIndex: Int

  /// Binding to the selection (for interactive menus).
  private let selectionBinding: Binding<Int>?

  /// Callback when an item is selected (Enter or shortcut).
  private let onSelect: ((Int) -> Void)?

  /// The style for unselected items.
  let itemColor: Color?

  /// The style for the selected item.
  let selectedColor: Color?

  /// The indicator for the selected item.
  let selectionIndicator: String

  /// The border style (nil for no border).
  let borderStyle: BorderStyle?

  /// The border color.
  let borderColor: Color?

  /// Creates a static menu (non-interactive).
  ///
  /// - Parameters:
  ///   - title: The menu title (optional).
  ///   - items: The menu items.
  ///   - selectedIndex: The currently selected item index (default: 0).
  ///   - itemColor: The color for unselected items (default: theme foreground).
  ///   - selectedColor: The color for the selected item (default: theme accent).
  ///   - selectionIndicator: The indicator shown before selected item (default: "▶ ").
  ///   - borderStyle: The border style (default: appearance borderStyle, nil for no border).
  ///   - borderColor: The border color (default: theme border).
  public init(
    title: String? = nil,
    items: [MenuItem],
    selectedIndex: Int = 0,
    itemColor: Color? = nil,
    selectedColor: Color? = nil,
    selectionIndicator: String = "▶ ",
    borderStyle: BorderStyle? = nil,
    borderColor: Color? = nil
  ) {
    self.title = title
    self.items = items
    self.selectedIndex = max(0, min(selectedIndex, items.count - 1))
    self.selectionBinding = nil
    self.onSelect = nil
    self.itemColor = itemColor
    self.selectedColor = selectedColor
    self.selectionIndicator = selectionIndicator
    self.borderStyle = borderStyle
    self.borderColor = borderColor
  }

  /// Creates an interactive menu with selection binding.
  ///
  /// - Parameters:
  ///   - title: The menu title (optional).
  ///   - items: The menu items.
  ///   - selection: Binding to the selected index.
  ///   - onSelect: Callback when item is activated (Enter or shortcut).
  ///   - itemColor: The color for unselected items (default: theme foreground).
  ///   - selectedColor: The color for the selected item (default: theme accent).
  ///   - selectionIndicator: The indicator shown before selected item (default: "▶ ").
  ///   - borderStyle: The border style (default: appearance borderStyle, nil for no border).
  ///   - borderColor: The border color (default: theme border).
  public init(
    title: String? = nil,
    items: [MenuItem],
    selection: Binding<Int>,
    onSelect: ((Int) -> Void)? = nil,
    itemColor: Color? = nil,
    selectedColor: Color? = nil,
    selectionIndicator: String = "▶ ",
    borderStyle: BorderStyle? = nil,
    borderColor: Color? = nil
  ) {
    self.title = title
    self.items = items
    self.selectedIndex = max(0, min(selection.wrappedValue, items.count - 1))
    self.selectionBinding = selection
    self.onSelect = onSelect
    self.itemColor = itemColor
    self.selectedColor = selectedColor
    self.selectionIndicator = selectionIndicator
    self.borderStyle = borderStyle
    self.borderColor = borderColor
  }

  public var body: some View {
    _MenuCore(
      title: title,
      items: items,
      selectedIndex: selectedIndex,
      selectionBinding: selectionBinding,
      onSelect: onSelect,
      itemColor: itemColor,
      selectedColor: selectedColor,
      selectionIndicator: selectionIndicator,
      borderStyle: borderStyle,
      borderColor: borderColor
    )
  }
}
