//  TUIKit - Terminal UI Kit for Swift
//  TextFieldHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A focus handler for text field components.
///
/// `TextFieldHandler` manages text editing state and keyboard input for
/// `TextField`. It handles:
/// - Character insertion at cursor position
/// - Backspace/delete for removing characters
/// - Cursor navigation (left/right/home/end)
/// - Text selection with Shift+Arrow keys
/// - Copy/Cut/Paste via system clipboard
/// - Submit action on Enter
///
/// ## Usage
///
/// ```swift
/// // In TextField's renderToBuffer:
/// let handler = TextFieldHandler(
///     focusID: focusID,
///     text: textBinding,
///     canBeFocused: !isDisabled
/// )
/// handler.onSubmit = submitAction
/// focusManager.register(handler, inSection: sectionID)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert character at cursor (replaces selection) |
/// | Backspace | Delete selection or character before cursor |
/// | Delete | Delete selection or character at cursor |
/// | Left | Move cursor left (clears selection) |
/// | Right | Move cursor right (clears selection) |
/// | Home | Move cursor to start (clears selection) |
/// | End | Move cursor to end (clears selection) |
/// | Shift+Left | Extend selection left |
/// | Shift+Right | Extend selection right |
/// | Shift+Up | Select to start of text |
/// | Shift+Down | Select to end of text |
/// | Shift+Home | Select to start of text |
/// | Shift+End | Select to end of text |
/// | Ctrl+A | Select all text |
/// | Ctrl+C | Copy selection to clipboard |
/// | Ctrl+X | Cut selection to clipboard |
/// | Ctrl+V | Paste from clipboard |
/// | Ctrl+Z | Undo last change |
/// | Enter | Trigger submit action |
final class TextFieldHandler: Focusable {
  /// The unique identifier for this focusable element.
  let focusID: String

  /// The binding to the text content.
  var text: Binding<String>

  /// Whether this element can currently receive focus.
  var canBeFocused: Bool

  /// The cursor position (character index where next input will be inserted).
  var cursorPosition: Int

  /// The selection anchor position (where selection started).
  /// When nil, there is no active selection.
  /// When set, the selection spans from `selectionAnchor` to `cursorPosition`.
  var selectionAnchor: Int?

  /// Callback triggered when the user presses Enter.
  var onSubmit: (() -> Void)?

  /// The text content type used for input character filtering.
  ///
  /// When set, both typed characters and pasted text are filtered against
  /// the allowed character set of the content type. Synced from the
  /// environment during each render pass.
  var textContentType: TextContentType?

  /// Undo history stack storing previous text states and cursor positions.
  private var undoStack: [(text: String, cursor: Int)] = []

  /// Maximum number of undo states to keep.
  private let maxUndoStates = 50

  /// Creates a text field handler.
  ///
  /// - Parameters:
  ///   - focusID: The unique focus identifier.
  ///   - text: The binding to the text content.
  ///   - canBeFocused: Whether this element can receive focus. Defaults to `true`.
  ///   - cursorPosition: The initial cursor position. Defaults to end of text.
  init(
    focusID: String,
    text: Binding<String>,
    canBeFocused: Bool = true,
    cursorPosition: Int? = nil
  ) {
    self.focusID = focusID
    self.text = text
    self.canBeFocused = canBeFocused
    self.cursorPosition = cursorPosition ?? text.wrappedValue.count
    self.selectionAnchor = nil
  }
}

// MARK: - Undo

extension TextFieldHandler {
  /// Pushes the current state onto the undo stack.
  func pushUndoState() {
    let state = (text: text.wrappedValue, cursor: cursorPosition)

    // Avoid duplicate states
    if let last = undoStack.last, last.text == state.text {
      return
    }

    undoStack.append(state)

    // Limit stack size
    if undoStack.count > maxUndoStates {
      undoStack.removeFirst()
    }
  }

  /// Restores the previous text state from the undo stack.
  func undo() {
    guard let previous = undoStack.popLast() else { return }
    text.wrappedValue = previous.text
    cursorPosition = min(previous.cursor, previous.text.count)
    clearSelection()
  }
}

// MARK: - Focus Lifecycle

extension TextFieldHandler {
  func onFocusReceived() {
    // Ensure cursor is at a valid position
    clampCursorPosition()
  }

  func onFocusLost() {
    // Nothing special needed when losing focus
  }
}
