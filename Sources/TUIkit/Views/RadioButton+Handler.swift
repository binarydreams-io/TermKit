//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButton+Handler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Radio Button Handler

/// Internal handler class for radio button group focus and selection management.
///
/// Persisted across renders via StateStorage to maintain focusedIndex and enable
/// Tab navigation between radio button groups.
final class RadioButtonGroupHandler: Focusable {
  let focusID: String
  var selection: Binding<AnyHashable>
  var itemValues: [AnyHashable]
  let orientation: RadioButtonOrientation
  var canBeFocused: Bool

  /// The currently focused item index within the group.
  /// Persisted across renders to maintain focus position.
  var focusedIndex: Int = 0

  init(
    focusID: String,
    selection: Binding<AnyHashable>,
    itemValues: [AnyHashable],
    orientation: RadioButtonOrientation,
    canBeFocused: Bool
  ) {
    self.focusID = focusID
    self.selection = selection
    self.itemValues = itemValues
    self.orientation = orientation
    self.canBeFocused = canBeFocused

    // Find current focused index based on selection
    if let currentIndex = itemValues.firstIndex(of: selection.wrappedValue) {
      self.focusedIndex = currentIndex
    }
  }
}

// MARK: - Focus Lifecycle

extension RadioButtonGroupHandler {
  func onFocusLost() {
    // Reset focusedIndex to the selected item when the group loses focus
    if let selectedIndex = itemValues.firstIndex(of: selection.wrappedValue) {
      focusedIndex = selectedIndex
    }
  }
}

// MARK: - Key Event Handling

extension RadioButtonGroupHandler {
  func handleKeyEvent(_ event: KeyEvent) -> Bool {
    switch event.key {
    case .up:
      // Vertical: navigate focus up (don't change selection); Horizontal: consume but do nothing
      if orientation == .vertical {
        focusedIndex = focusedIndex > 0 ? focusedIndex - 1 : itemValues.count - 1
      }
      return true

    case .down:
      // Vertical: navigate focus down (don't change selection); Horizontal: consume but do nothing
      if orientation == .vertical {
        focusedIndex = focusedIndex < itemValues.count - 1 ? focusedIndex + 1 : 0
      }
      return true

    case .left:
      // Horizontal: navigate focus left (don't change selection); Vertical: consume but do nothing
      if orientation == .horizontal {
        focusedIndex = focusedIndex > 0 ? focusedIndex - 1 : itemValues.count - 1
      }
      return true

    case .right:
      // Horizontal: navigate focus right (don't change selection); Vertical: consume but do nothing
      if orientation == .horizontal {
        focusedIndex = focusedIndex < itemValues.count - 1 ? focusedIndex + 1 : 0
      }
      return true

    case .enter, .space:
      // Select the currently focused item (make it the selection)
      selection.wrappedValue = itemValues[focusedIndex]
      return true

    default:
      return false
    }
  }
}
