//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Table.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Table

/// A scrollable table with columns, keyboard navigation, and selection.
///
/// `Table` displays tabular data inside a bordered container with:
/// - Column headers in the container header section
/// - Optional footer section
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single or multi-selection via bindings
/// - Configurable column widths (fixed, flexible, ratio)
/// - Column alignment (leading, center, trailing)
/// - ANSI-aware column layout
/// - Scrolling with automatic viewport management
///
/// ## Usage
///
/// ```swift
/// struct FileInfo: Identifiable {
///     let id: String
///     let name: String
///     let size: String
///     let modified: String
/// }
///
/// @State var selectedID: String?
///
/// Table(files, selection: $selectedID) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Size", value: \.size)
///         .width(.fixed(10))
///         .alignment(.trailing)
///     TableColumn("Modified", value: \.modified)
///         .width(.ratio(0.3))
/// }
/// ```
///
/// ## Column Spacing
///
/// Columns are separated by spaces (no vertical lines) for a clean look.
public struct Table<Value: Identifiable & Sendable>: View where Value.ID: Hashable {
  /// The data items to display.
  let data: [Value]

  /// The column definitions.
  let columns: [TableColumn<Value>]

  /// Binding for single selection (optional ID).
  let singleSelection: Binding<Value.ID?>?

  /// Binding for multi-selection (Set of IDs).
  let multiSelection: Binding<Set<Value.ID>>?

  /// The selection mode derived from which binding is set.
  var selectionMode: SelectionMode {
    multiSelection != nil ? .multi : .single
  }

  /// The unique focus identifier for this table.
  let focusID: String?

  /// Whether the table is disabled.
  var isDisabled: Bool

  /// The placeholder text shown when the table is empty.
  let emptyPlaceholder: String

  /// The spacing between columns in characters.
  let columnSpacing: Int

  public var body: some View {
    _TableCore(
      data: data,
      columns: columns,
      singleSelection: singleSelection,
      multiSelection: multiSelection,
      selectionMode: selectionMode,
      focusID: focusID,
      isDisabled: isDisabled,
      emptyPlaceholder: emptyPlaceholder,
      columnSpacing: columnSpacing
    )
  }
}

// MARK: - Single Selection Initializer

extension Table {
  // Creates a table with single selection.
  //
  // - Parameters:
  //   - data: The data items to display.
  //   - selection: A binding to the selected item's ID (nil = no selection).
  //   - focusID: The unique focus identifier (default: auto-generated).

  ///   - columnSpacing: Spacing between columns (default: 2).
  ///   - emptyPlaceholder: Placeholder text when empty (default: "No items").
  ///   - columns: A builder that defines the table columns.
  public init(
    _ data: [Value],
    selection: Binding<Value.ID?>,
    focusID: String? = nil,

    columnSpacing: Int = 2,
    emptyPlaceholder: String = "No items",
    @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
  ) {
    self.data = data
    self.columns = columns()
    self.singleSelection = selection
    self.multiSelection = nil
    self.focusID = focusID
    self.isDisabled = false

    self.columnSpacing = columnSpacing
    self.emptyPlaceholder = emptyPlaceholder
  }
}

// MARK: - Multi Selection Initializer

extension Table {
  // Creates a table with multi-selection.
  //
  // - Parameters:
  //   - data: The data items to display.
  //   - selection: A binding to the set of selected item IDs.
  //   - focusID: The unique focus identifier (default: auto-generated).

  ///   - columnSpacing: Spacing between columns (default: 2).
  ///   - emptyPlaceholder: Placeholder text when empty (default: "No items").
  ///   - columns: A builder that defines the table columns.
  public init(
    _ data: [Value],
    selection: Binding<Set<Value.ID>>,
    focusID: String? = nil,

    columnSpacing: Int = 2,
    emptyPlaceholder: String = "No items",
    @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
  ) {
    self.data = data
    self.columns = columns()
    self.singleSelection = nil
    self.multiSelection = selection
    self.focusID = focusID
    self.isDisabled = false

    self.columnSpacing = columnSpacing
    self.emptyPlaceholder = emptyPlaceholder
  }
}

// MARK: - Convenience Modifiers

extension Table {
  /// Creates a disabled version of this table.
  ///
  /// - Parameter disabled: Whether the table is disabled.
  /// - Returns: A new table with the disabled state.
  public func disabled(_ disabled: Bool = true) -> Table {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }
}
