//  🖥️ TUIKit — Terminal UI Kit for Swift
//  List+Modifiers.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Convenience Modifiers

extension List {
  /// Creates a disabled version of this list.
  ///
  /// - Parameter disabled: Whether the list is disabled.
  /// - Returns: A new list with the disabled state.
  public func disabled(_ disabled: Bool = true) -> List<SelectionValue, Content, Footer> {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }

  /// Sets an explicit focus identifier for this list.
  ///
  /// By default, lists generate a focus identifier from their position
  /// in the view hierarchy. Use this modifier when you need a stable,
  /// explicit identifier for programmatic focus management.
  ///
  /// - Parameter id: The focus identifier.
  /// - Returns: A list with the specified focus identifier.
  public func focusID(_ id: String) -> List<SelectionValue, Content, Footer> {
    var copy = self
    copy.focusID = id
    return copy
  }

  /// Sets the placeholder text displayed when the list has no items.
  ///
  /// - Parameter placeholder: The text to show when the list is empty.
  /// - Returns: A list with the specified empty placeholder.
  public func listEmptyPlaceholder(_ placeholder: String) -> List<SelectionValue, Content, Footer> {
    var copy = self
    copy.emptyPlaceholder = placeholder
    return copy
  }

  /// Controls whether a separator line is shown before the footer.
  ///
  /// - Parameter show: Whether to show the footer separator. Defaults to `true`.
  /// - Returns: A list with the specified footer separator visibility.
  public func listFooterSeparator(_ show: Bool = true) -> List<SelectionValue, Content, Footer> {
    var copy = self
    copy.showFooterSeparator = show
    return copy
  }
}
