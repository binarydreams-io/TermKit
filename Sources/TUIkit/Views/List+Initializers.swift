//  🖥️ TUIKit — Terminal UI Kit for Swift
//  List+Initializers.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Single Selection Initializers (with Footer)

extension List {
  /// Creates a list with single selection, title, and footer.
  ///
  /// - Parameters:
  ///   - title: The title displayed in the border.
  ///   - selection: A binding to the selected item's ID (nil = no selection).
  ///   - content: A ViewBuilder that defines the list content.
  ///   - footer: A ViewBuilder that defines the footer content.
  public init(
    _ title: String,
    selection: Binding<SelectionValue?>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.title = title
    self.content = content()
    self.footer = footer()
    self.singleSelection = selection
    self.multiSelection = nil
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = true
  }

  /// Creates a list with single selection and footer, without a title.
  ///
  /// - Parameters:
  ///   - selection: A binding to the selected item's ID (nil = no selection).
  ///   - content: A ViewBuilder that defines the list content.
  ///   - footer: A ViewBuilder that defines the footer content.
  public init(
    selection: Binding<SelectionValue?>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.title = nil
    self.content = content()
    self.footer = footer()
    self.singleSelection = selection
    self.multiSelection = nil
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = true
  }
}

// MARK: - Single Selection Initializers (without Footer)

extension List where Footer == EmptyView {
  /// Creates a list with single selection and a title.
  ///
  /// - Parameters:
  ///   - title: The title displayed in the border.
  ///   - selection: A binding to the selected item's ID (nil = no selection).
  ///   - content: A ViewBuilder that defines the list content.
  public init(
    _ title: String,
    selection: Binding<SelectionValue?>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.content = content()
    self.footer = nil
    self.singleSelection = selection
    self.multiSelection = nil
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = false
  }

  /// Creates a list with single selection without a title.
  ///
  /// - Parameters:
  ///   - selection: A binding to the selected item's ID (nil = no selection).
  ///   - content: A ViewBuilder that defines the list content.
  public init(
    selection: Binding<SelectionValue?>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = nil
    self.content = content()
    self.footer = nil
    self.singleSelection = selection
    self.multiSelection = nil
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = false
  }
}

// MARK: - Multi Selection Initializers (with Footer)

extension List {
  /// Creates a list with multi-selection, title, and footer.
  ///
  /// - Parameters:
  ///   - title: The title displayed in the border.
  ///   - selection: A binding to the set of selected item IDs.
  ///   - content: A ViewBuilder that defines the list content.
  ///   - footer: A ViewBuilder that defines the footer content.
  public init(
    _ title: String,
    selection: Binding<Set<SelectionValue>>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.title = title
    self.content = content()
    self.footer = footer()
    self.singleSelection = nil
    self.multiSelection = selection
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = true
  }

  /// Creates a list with multi-selection and footer, without a title.
  ///
  /// - Parameters:
  ///   - selection: A binding to the set of selected item IDs.
  ///   - content: A ViewBuilder that defines the list content.
  ///   - footer: A ViewBuilder that defines the footer content.
  public init(
    selection: Binding<Set<SelectionValue>>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.title = nil
    self.content = content()
    self.footer = footer()
    self.singleSelection = nil
    self.multiSelection = selection
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = true
  }
}

// MARK: - Multi Selection Initializers (without Footer)

extension List where Footer == EmptyView {
  /// Creates a list with multi-selection and a title.
  ///
  /// - Parameters:
  ///   - title: The title displayed in the border.
  ///   - selection: A binding to the set of selected item IDs.
  ///   - content: A ViewBuilder that defines the list content.
  public init(
    _ title: String,
    selection: Binding<Set<SelectionValue>>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.content = content()
    self.footer = nil
    self.singleSelection = nil
    self.multiSelection = selection
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = false
  }

  /// Creates a list with multi-selection without a title.
  ///
  /// - Parameters:
  ///   - selection: A binding to the set of selected item IDs.
  ///   - content: A ViewBuilder that defines the list content.
  public init(
    selection: Binding<Set<SelectionValue>>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = nil
    self.content = content()
    self.footer = nil
    self.singleSelection = nil
    self.multiSelection = selection
    self.focusID = nil
    self.isDisabled = false
    self.emptyPlaceholder = ViewConstants.emptyListPlaceholder
    self.showFooterSeparator = false
  }
}
