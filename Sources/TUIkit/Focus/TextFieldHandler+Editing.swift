//  TUIKit - Terminal UI Kit for Swift
//  TextFieldHandler+Editing.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Selection

extension TextFieldHandler {
  /// Returns the current selection range, or nil if no selection.
  ///
  /// The range is always normalized (start < end) regardless of
  /// whether the user selected left-to-right or right-to-left.
  var selectionRange: Range<Int>? {
    guard let anchor = selectionAnchor else { return nil }
    guard anchor != cursorPosition else { return nil } // Empty selection
    let start = min(anchor, cursorPosition)
    let end = max(anchor, cursorPosition)
    return start ..< end
  }

  /// Returns true if there is an active text selection.
  var hasSelection: Bool {
    selectionRange != nil
  }

  /// Clears the current selection without moving the cursor.
  func clearSelection() {
    selectionAnchor = nil
  }

  /// Starts or extends a selection from the current cursor position.
  ///
  /// If no selection exists, sets the anchor at the current cursor position.
  /// If a selection exists, the anchor stays where it is.
  func startOrExtendSelection() {
    if selectionAnchor == nil {
      selectionAnchor = cursorPosition
    }
  }

  /// Deletes the text in the given range and positions cursor at start.
  ///
  /// Pushes the current state to the undo stack before deleting.
  ///
  /// - Parameter range: The range of characters to delete.
  func deleteRange(_ range: Range<Int>) {
    pushUndoState()
    deleteRangeWithoutUndo(range)
  }

  /// Deletes the text in the given range without pushing to undo stack.
  ///
  /// Used internally when undo state has already been pushed.
  ///
  /// - Parameter range: The range of characters to delete.
  func deleteRangeWithoutUndo(_ range: Range<Int>) {
    var current = text.wrappedValue
    let startIndex = current.index(current.startIndex, offsetBy: range.lowerBound)
    let endIndex = current.index(current.startIndex, offsetBy: range.upperBound)
    current.removeSubrange(startIndex ..< endIndex)
    text.wrappedValue = current
    cursorPosition = range.lowerBound
  }

  /// Extends selection one character to the left.
  func extendSelectionLeft() {
    startOrExtendSelection()
    if cursorPosition > 0 {
      cursorPosition -= 1
    }
  }

  /// Extends selection one character to the right.
  func extendSelectionRight() {
    startOrExtendSelection()
    if cursorPosition < text.wrappedValue.count {
      cursorPosition += 1
    }
  }

  /// Extends selection to the start of the text.
  func extendSelectionToStart() {
    startOrExtendSelection()
    cursorPosition = 0
  }

  /// Extends selection to the end of the text.
  func extendSelectionToEnd() {
    startOrExtendSelection()
    cursorPosition = text.wrappedValue.count
  }
}

// MARK: - Text Editing

extension TextFieldHandler {
  /// Inserts a character at the current cursor position.
  ///
  /// If text is selected, the selection is replaced with the character.
  ///
  /// - Parameter char: The character to insert.
  func insertCharacter(_ char: Character) {
    guard textContentType?.isAllowed(char) ?? true else { return }

    pushUndoState()

    // Replace selection if present
    if let range = selectionRange {
      deleteRangeWithoutUndo(range)
      clearSelection()
    }

    var current = text.wrappedValue
    let index = current.index(current.startIndex, offsetBy: min(cursorPosition, current.count))
    current.insert(char, at: index)
    text.wrappedValue = current
    cursorPosition += 1
  }

  /// Deletes the character before the cursor (backspace).
  ///
  /// If text is selected, the entire selection is deleted.
  func deleteBackward() {
    // Delete selection if present
    if let range = selectionRange {
      pushUndoState()
      deleteRangeWithoutUndo(range)
      clearSelection()
      return
    }

    guard cursorPosition > 0 else { return }
    pushUndoState()
    var current = text.wrappedValue
    let index = current.index(current.startIndex, offsetBy: cursorPosition - 1)
    current.remove(at: index)
    text.wrappedValue = current
    cursorPosition -= 1
  }

  /// Deletes the character at the cursor position (delete key).
  ///
  /// If text is selected, the entire selection is deleted.
  func deleteForward() {
    // Delete selection if present
    if let range = selectionRange {
      pushUndoState()
      deleteRangeWithoutUndo(range)
      clearSelection()
      return
    }

    var current = text.wrappedValue
    guard cursorPosition < current.count else { return }
    pushUndoState()
    let index = current.index(current.startIndex, offsetBy: cursorPosition)
    current.remove(at: index)
    text.wrappedValue = current
  }
}

// MARK: - Cursor Navigation

extension TextFieldHandler {
  /// Moves the cursor one position to the left.
  func moveCursorLeft() {
    if cursorPosition > 0 {
      cursorPosition -= 1
    }
  }

  /// Moves the cursor one position to the right.
  func moveCursorRight() {
    if cursorPosition < text.wrappedValue.count {
      cursorPosition += 1
    }
  }

  /// Ensures the cursor position and selection anchor are within valid bounds.
  func clampCursorPosition() {
    let maxPos = text.wrappedValue.count
    cursorPosition = max(0, min(cursorPosition, maxPos))
    if let anchor = selectionAnchor {
      selectionAnchor = max(0, min(anchor, maxPos))
    }
  }
}
