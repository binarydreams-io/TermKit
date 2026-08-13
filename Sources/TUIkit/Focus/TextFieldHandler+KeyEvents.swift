//  TUIKit - Terminal UI Kit for Swift
//  TextFieldHandler+KeyEvents.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Event Handling

extension TextFieldHandler {
  func handleKeyEvent(_ event: KeyEvent) -> Bool {
    switch event.key {
    case .space:
      insertCharacter(" ")
      return true

    case let .character(char):
      return handleCharacter(char, ctrl: event.ctrl)

    case .backspace:
      deleteBackward()
      return true

    case .delete:
      deleteForward()
      return true

    case .left, .right, .up, .down, .home, .end:
      return handleNavigation(event.key, extendingSelection: event.shift)

    case .enter:
      onSubmit?()
      return true

    case let .paste(text):
      insertText(text)
      return true

    default:
      return false
    }
  }

  /// Handles printable characters and Ctrl-based editing shortcuts.
  private func handleCharacter(_ char: Character, ctrl: Bool) -> Bool {
    if ctrl {
      switch char {
      case "a", "A": selectAll()
      case "c", "C": copySelection()
      case "x", "X": cutSelection()
      case "v", "V": paste()
      case "z", "Z": undo()
      default: return false
      }
      return true
    }

    guard char.isLetter || char.isNumber || char.isPunctuation ||
      char.isSymbol || char.isWhitespace
    else {
      return false
    }
    insertCharacter(char)
    return true
  }

  /// Handles cursor navigation with optional selection extension.
  private func handleNavigation(_ key: Key, extendingSelection: Bool) -> Bool {
    switch key {
    case .left:
      if extendingSelection {
        extendSelectionLeft()
      } else {
        moveLeftClearingSelection()
      }
    case .right:
      if extendingSelection {
        extendSelectionRight()
      } else {
        moveRightClearingSelection()
      }
    case .up, .home:
      if extendingSelection {
        extendSelectionToStart()
      } else {
        moveToStartClearingSelection()
      }
    case .down, .end:
      if extendingSelection {
        extendSelectionToEnd()
      } else {
        moveToEndClearingSelection()
      }
    default:
      return false
    }
    return true
  }

  private func moveLeftClearingSelection() {
    clearSelection()
    moveCursorLeft()
  }

  private func moveRightClearingSelection() {
    clearSelection()
    moveCursorRight()
  }

  private func moveToStartClearingSelection() {
    clearSelection()
    cursorPosition = 0
  }

  private func moveToEndClearingSelection() {
    clearSelection()
    cursorPosition = text.wrappedValue.count
  }
}
