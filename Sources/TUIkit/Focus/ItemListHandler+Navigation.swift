//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Navigation.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Event Handling

extension ItemListHandler {
  func handleKeyEvent(_ event: KeyEvent) -> Bool {
    guard itemCount > 0 else { return false }

    switch event.key {
    case .up:
      moveFocus(by: -1, wrap: true)
      return true

    case .down:
      moveFocus(by: 1, wrap: true)
      return true

    case .home:
      if selectableIndices.isEmpty {
        updateFocus(to: 0)
      } else if let firstSelectable = selectableIndices.min() {
        updateFocus(to: firstSelectable)
      } else {
        return false
      }
      return true

    case .end:
      if selectableIndices.isEmpty {
        updateFocus(to: itemCount - 1)
      } else if let lastSelectable = selectableIndices.max() {
        updateFocus(to: lastSelectable)
      } else {
        return false
      }
      return true

    case .pageUp:
      moveFocus(by: -viewportHeight, wrap: false)
      return true

    case .pageDown:
      moveFocus(by: viewportHeight, wrap: false)
      return true

    case .enter, .space:
      toggleSelectionAtFocusedIndex()
      return true

    default:
      return false
    }
  }
}

// MARK: - Navigation Helpers

extension ItemListHandler {
  /// Moves focus by the given delta, optionally wrapping around.
  ///
  /// - Parameters:
  ///   - delta: The number of items to move (negative = up, positive = down).
  ///   - wrap: Whether to wrap around at boundaries.
  func moveFocus(by delta: Int, wrap: Bool) {
    guard itemCount > 0 else { return }

    var newIndex = focusedIndex + delta

    // If selectableIndices is populated, skip non-selectable rows
    if !selectableIndices.isEmpty {
      let maxAttempts = itemCount + 1
      var attempts = 0

      // Keep moving until we find a selectable index or hit max attempts
      while attempts < maxAttempts {
        if wrap {
          // Wrap around: -1 becomes last, count becomes 0
          newIndex = ((newIndex % itemCount) + itemCount) % itemCount
        } else {
          // Clamp to valid range and stop if out of bounds
          if newIndex < 0 || newIndex >= itemCount {
            return
          }
        }

        // Check if this index is selectable
        if selectableIndices.contains(newIndex) {
          break
        }

        newIndex += delta
        attempts += 1
      }

      // If we couldn't find a selectable index, don't move
      if attempts >= maxAttempts {
        return
      }
    } else {
      // Backward compatibility: all items are selectable
      if wrap {
        // Wrap around: -1 becomes last, count becomes 0
        newIndex = ((newIndex % itemCount) + itemCount) % itemCount
      } else {
        // Clamp to valid range
        newIndex = max(0, min(itemCount - 1, newIndex))
      }
    }

    updateFocus(to: newIndex)
  }

  @discardableResult
  func moveFocusBySelectableRows(by delta: Int) -> Bool {
    guard itemCount > 0, delta != 0 else { return false }

    let indices: [Int] = if selectableIndices.isEmpty {
      if itemIDs.isEmpty {
        Array(0 ..< itemCount)
      } else {
        itemIDs.indices.filter { $0 < itemCount && itemIDs[$0] != nil }
      }
    } else {
      selectableIndices.filter { $0 >= 0 && $0 < itemCount }.sorted()
    }
    guard !indices.isEmpty else { return false }

    let currentPosition = indices.firstIndex(of: focusedIndex)
    let targetPosition: Int
    if let currentPosition {
      targetPosition = currentPosition + delta
    } else if delta > 0 {
      let insertion = indices.firstIndex(where: { $0 > focusedIndex }) ?? indices.count
      targetPosition = insertion - 1 + delta
    } else {
      let insertion = indices.firstIndex(where: { $0 >= focusedIndex }) ?? indices.count
      targetPosition = insertion + delta
    }

    let clampedPosition = max(0, min(indices.count - 1, targetPosition))
    let newIndex = indices[clampedPosition]
    guard newIndex != focusedIndex else { return false }

    return updateFocus(to: newIndex)
  }

  @discardableResult
  func updateFocus(to newIndex: Int) -> Bool {
    let previousIndex = focusedIndex
    let previousScrollOffset = scrollOffset

    focusedIndex = max(0, min(itemCount - 1, newIndex))
    ensureFocusedItemVisible()

    let didChange = focusedIndex != previousIndex || scrollOffset != previousScrollOffset
    if didChange {
      onVisualStateChange()
    }
    return didChange
  }

  /// Adjusts scroll offset to keep the focused item visible.
  func ensureFocusedItemVisible() {
    guard viewportHeight > 0 else { return }

    if !rowHeights.isEmpty {
      scrollOffset = max(0, min(itemCount - 1, scrollOffset))

      if focusedIndex < scrollOffset {
        scrollOffset = focusedIndex
      } else if !visibleRange.contains(focusedIndex) {
        scrollOffset = focusedIndex
        var precedingLines = 0

        while scrollOffset > 0 {
          let previousIndex = scrollOffset - 1
          let previousHeight = rowHeight(at: previousIndex)
          guard precedingLines + previousHeight < viewportHeight else { break }

          precedingLines += previousHeight
          scrollOffset = previousIndex
        }
      }

      scrollOffset = max(0, min(itemCount - 1, scrollOffset))
      return
    }

    // If focused item is above the viewport, scroll up
    if focusedIndex < scrollOffset {
      scrollOffset = focusedIndex
    }

    // If focused item is below the viewport, scroll down
    if focusedIndex >= scrollOffset + viewportHeight {
      scrollOffset = focusedIndex - viewportHeight + 1
    }

    // Clamp scroll offset to valid range
    let maxOffset = max(0, itemCount - viewportHeight)
    scrollOffset = max(0, min(maxOffset, scrollOffset))
  }
}

// MARK: - Scroll Indicator State

extension ItemListHandler {
  /// Whether there is content above the visible viewport.
  var hasContentAbove: Bool {
    scrollOffset > 0
  }

  /// Whether there is content below the visible viewport.
  var hasContentBelow: Bool {
    visibleRange.upperBound < itemCount
  }

  /// The range of visible item indices.
  var visibleRange: Range<Int> {
    let start = max(0, min(scrollOffset, itemCount))
    guard start < itemCount, viewportHeight > 0 else { return start ..< start }

    if rowHeights.isEmpty {
      let end = min(start + viewportHeight, itemCount)
      return start ..< end
    }

    var end = start
    var linesUsed = 0
    while end < itemCount, linesUsed < viewportHeight {
      linesUsed += rowHeight(at: end)
      end += 1
    }

    return start ..< end
  }

  private func rowHeight(at index: Int) -> Int {
    guard rowHeights.indices.contains(index) else { return 1 }
    return max(1, rowHeights[index])
  }
}
