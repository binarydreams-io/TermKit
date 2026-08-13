//  TUIKit - Terminal UI Kit for Swift
//  TabView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TabItem

/// One tab's data: the value it selects, its label, and an optional badge.
public struct TabItem<Value: Hashable & Sendable>: Equatable, Sendable {
  /// The value this tab selects.
  public let value: Value

  /// The tab's display label.
  public let label: String

  /// An optional badge shown after the label, e.g. a count.
  public var badge: String?

  /// An optional key hint shown before the label, e.g. the digit that selects
  /// the tab.
  ///
  /// The bar prints the hint on an unselected tab only, because the selected
  /// tab spends that column on its own mark. A tab without a hint prints its
  /// label alone. The hint is data, not a view option, so it belongs to the
  /// item and not to a modifier.
  public var hint: String?

  /// Creates a tab item.
  ///
  /// - Parameters:
  ///   - label: The tab's display label.
  ///   - value: The value this tab selects.
  ///   - badge: An optional badge shown after the label.
  ///   - hint: An optional key hint shown before the label.
  public init(_ label: String, value: Value, badge: String? = nil, hint: String? = nil) {
    self.label = label
    self.value = value
    self.badge = badge
    self.hint = hint
  }
}

// MARK: - TabView

/// A clickable tab bar above a single piece of selected content.
///
/// ```swift
/// @State private var selection = "rules"
///
/// TabView(selection: $selection, tabs: [
///     TabItem("Rules", value: "rules", badge: "12"),
///     TabItem("Skills", value: "skills"),
/// ]) { value in
///     Text("Showing \(value)")
/// }
/// ```
///
/// ## Differences from SwiftUI
///
/// SwiftUI's `TabView` takes each tab as a child view tagged with
/// `.tag(_:)`, and type-erases the tabs internally with `AnyView`. TUIkit
/// has neither `AnyView` nor tab traits, so `TabView` declares its tabs as
/// data (``TabItem``) up front and hands the current selection to a single
/// `content` closure. Only the selected tab's content ever renders — the
/// unselected tabs exist only as bar labels.
public struct TabView<SelectionValue: Hashable & Sendable, Content: View>: View {
  /// The binding to the selected tab's value.
  let selection: Binding<SelectionValue>

  /// The tabs shown in the bar, in display order.
  let tabs: [TabItem<SelectionValue>]

  /// Builds the content for the selected value.
  let content: (SelectionValue) -> Content

  /// Creates a tab view.
  ///
  /// - Parameters:
  ///   - selection: A binding to the selected tab's value.
  ///   - tabs: The tabs shown in the bar, in display order.
  ///   - content: A closure that builds the content for the selected value.
  public init(
    selection: Binding<SelectionValue>,
    tabs: [TabItem<SelectionValue>],
    @ViewBuilder content: @escaping (SelectionValue) -> Content
  ) {
    self.selection = selection
    self.tabs = tabs
    self.content = content
  }
}
