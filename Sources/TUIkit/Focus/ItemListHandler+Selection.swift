//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Selection.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Selection Helpers

extension ItemListHandler {
  /// Toggles the selection state at the focused index.
  func toggleSelectionAtFocusedIndex() {
    guard focusedIndex >= 0, focusedIndex < itemIDs.count,
          let itemID = itemIDs[focusedIndex]
    else { return }

    switch selectionMode {
    case .single:
      // Single selection: set to this item (or nil if already selected to deselect)
      if singleSelection?.wrappedValue == itemID {
        singleSelection?.wrappedValue = nil
      } else {
        singleSelection?.wrappedValue = itemID
      }

    case .multi:
      // Multi-selection: toggle this item in the set
      if var current = multiSelection?.wrappedValue {
        if current.contains(itemID) {
          current.remove(itemID)
        } else {
          current.insert(itemID)
        }
        multiSelection?.wrappedValue = current
      }
    }
  }

  /// Returns whether the item at the given index is selected.
  ///
  /// - Parameter index: The item index.
  /// - Returns: True if the item is selected.
  func isSelected(at index: Int) -> Bool {
    guard index >= 0, index < itemIDs.count,
          let itemID = itemIDs[index]
    else { return false }

    switch selectionMode {
    case .single:
      return singleSelection?.wrappedValue == itemID
    case .multi:
      return multiSelection?.wrappedValue.contains(itemID) ?? false
    }
  }

  /// Returns whether the item at the given index is focused.
  ///
  /// - Parameter index: The item index.
  /// - Returns: True if the item is focused.
  func isFocused(at index: Int) -> Bool {
    focusedIndex == index
  }
}
