//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - NavigationSplitView

/// A view that presents views in two or three columns, where selections in
/// leading columns control presentations in subsequent columns.
///
/// You create a navigation split view with two or three columns, and typically
/// use it as the root view in a ``Scene``. People choose one or more items in
/// a leading column to display details about those items in subsequent columns.
///
/// ## Two-Column Layout
///
/// To create a two-column navigation split view, use the
/// ``init(sidebar:detail:)`` initializer:
///
/// ```swift
/// @State private var selectedID: String?
///
/// var body: some View {
///     NavigationSplitView {
///         List("Items", selection: $selectedID) {
///             ForEach(items) { item in
///                 Text(item.name)
///             }
///         }
///     } detail: {
///         if let id = selectedID {
///             DetailView(itemID: id)
///         } else {
///             Text("Select an item")
///         }
///     }
/// }
/// ```
///
/// ## Three-Column Layout
///
/// To create a three-column view, use the ``init(sidebar:content:detail:)``
/// initializer:
///
/// ```swift
/// @State private var categoryID: String?
/// @State private var itemID: String?
///
/// var body: some View {
///     NavigationSplitView {
///         List("Categories", selection: $categoryID) { ... }
///     } content: {
///         List("Items", selection: $itemID) { ... }
///     } detail: {
///         DetailView(itemID: itemID)
///     }
/// }
/// ```
///
/// ## Column Visibility
///
/// You can programmatically control column visibility using a
/// ``NavigationSplitViewVisibility`` binding:
///
/// ```swift
/// @State private var visibility = NavigationSplitViewVisibility.all
///
/// NavigationSplitView(columnVisibility: $visibility) {
///     SidebarView()
/// } detail: {
///     DetailView()
/// }
/// ```
///
/// ## Focus Navigation
///
/// Each column registers as a separate focus section. Use Tab/Shift+Tab to
/// move between columns, and Up/Down arrows to navigate within each column.
///
/// ## TUI-Specific Behavior
///
/// - Columns are separated by a vertical line character (`│`).
/// - The split view renders within the content area between AppHeader and StatusBar.
/// - Column widths are determined by the ``NavigationSplitViewStyle``.
/// - No automatic collapsing to stack (terminal width is typically sufficient).
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
  /// The sidebar column content.
  let sidebar: Sidebar

  /// The content column (only used in three-column layouts).
  let content: Content

  /// The detail column content.
  let detail: Detail

  /// Whether this is a three-column layout.
  let isThreeColumn: Bool

  /// Binding to column visibility (optional).
  let columnVisibility: Binding<NavigationSplitViewVisibility>?

  public var body: some View {
    _NavigationSplitViewCore(
      sidebar: sidebar,
      content: content,
      detail: detail,
      isThreeColumn: isThreeColumn,
      columnVisibility: columnVisibility
    )
  }
}

// MARK: - Two-Column Initializers

extension NavigationSplitView where Content == EmptyView {
  /// Creates a two-column navigation split view.
  ///
  /// - Parameters:
  ///   - sidebar: The view to show in the leading column.
  ///   - detail: The view to show in the detail area.
  public init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = EmptyView()
    self.detail = detail()
    self.isThreeColumn = false
    self.columnVisibility = nil
  }

  /// Creates a two-column navigation split view with programmatic visibility control.
  ///
  /// - Parameters:
  ///   - columnVisibility: A binding to state that controls the visibility of the sidebar.
  ///   - sidebar: The view to show in the leading column.
  ///   - detail: The view to show in the detail area.
  public init(
    columnVisibility: Binding<NavigationSplitViewVisibility>,
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = EmptyView()
    self.detail = detail()
    self.isThreeColumn = false
    self.columnVisibility = columnVisibility
  }
}

// MARK: - Three-Column Initializers

extension NavigationSplitView {
  /// Creates a three-column navigation split view.
  ///
  /// - Parameters:
  ///   - sidebar: The view to show in the leading column.
  ///   - content: The view to show in the middle column.
  ///   - detail: The view to show in the detail area.
  public init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = content()
    self.detail = detail()
    self.isThreeColumn = true
    self.columnVisibility = nil
  }

  /// Creates a three-column navigation split view with programmatic visibility control.
  ///
  /// - Parameters:
  ///   - columnVisibility: A binding to state that controls the visibility of leading columns.
  ///   - sidebar: The view to show in the leading column.
  ///   - content: The view to show in the middle column.
  ///   - detail: The view to show in the detail area.
  public init(
    columnVisibility: Binding<NavigationSplitViewVisibility>,
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = content()
    self.detail = detail()
    self.isThreeColumn = true
    self.columnVisibility = columnVisibility
  }
}

// MARK: - Equatable Conformance

extension NavigationSplitView: @preconcurrency Equatable where Sidebar: Equatable, Content: Equatable, Detail: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sidebar == rhs.sidebar &&
      lhs.content == rhs.content &&
      lhs.detail == rhs.detail &&
      lhs.isThreeColumn == rhs.isThreeColumn
  }
}
