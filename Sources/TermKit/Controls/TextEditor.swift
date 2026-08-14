import Foundation

/// A newline-normalized editable text document.
public struct TextDocument: Sendable, Hashable {
  /// The normalized document text.
  public private(set) var text: String

  /// Creates a document and normalizes line endings.
  /// - Complexity: O(n), where n is the text length.
  public init(_ text: String = "") {
    self.text = Self.normalized(text)
  }

  /// The number of extended grapheme clusters.
  /// - Complexity: O(n), where n is the text length.
  public var characterCount: Int {
    text.count
  }

  /// The document lines, including empty lines.
  /// - Complexity: O(n), where n is the text length.
  public var lines: [Substring] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
  }

  /// Returns text within a clamped character-offset range.
  /// - Complexity: O(n), where n is the document length.
  public func string(in range: Range<Int>) -> String {
    let bounds = clamped(range)
    let lower = text.index(text.startIndex, offsetBy: bounds.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: bounds.upperBound)
    return String(text[lower ..< upper])
  }

  /// Replaces a clamped character-offset range.
  /// - Complexity: O(n + m), where n is document length and m is replacement length.
  public mutating func replace(_ range: Range<Int>, with replacement: String) {
    let bounds = clamped(range)
    let lower = text.index(text.startIndex, offsetBy: bounds.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: bounds.upperBound)
    text.replaceSubrange(lower ..< upper, with: Self.normalized(replacement))
  }

  /// Returns the zero-based line and column at a character offset.
  /// - Complexity: O(n), where n is the traversed character count.
  public func lineAndColumn(at offset: Int) -> (line: Int, column: Int) {
    let target = min(max(0, offset), characterCount)
    var line = 0
    var column = 0
    for character in text.prefix(target) {
      if character == "\n" {
        line += 1
        column = 0
      } else {
        column += 1
      }
    }
    return (line, column)
  }

  /// Returns the clamped character offset for a line and column.
  /// - Complexity: O(n), where n is the document length.
  public func offset(line targetLine: Int, column targetColumn: Int) -> Int {
    let line = max(0, targetLine)
    let column = max(0, targetColumn)
    var currentLine = 0
    var currentColumn = 0
    var offset = 0

    for character in text {
      if currentLine == line, currentColumn == column {
        return offset
      }
      if character == "\n" {
        if currentLine == line {
          return offset
        }
        currentLine += 1
        currentColumn = 0
      } else if currentLine == line {
        currentColumn += 1
      }
      offset += 1
    }
    return offset
  }

  private func clamped(_ range: Range<Int>) -> Range<Int> {
    let lower = min(max(0, range.lowerBound), characterCount)
    let upper = min(max(lower, range.upperBound), characterCount)
    return lower ..< upper
  }

  private static func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
  }
}

/// A text selection represented by anchor and head offsets.
public struct TextSelection: Sendable, Hashable {
  /// The fixed selection endpoint.
  public var anchor: Int
  /// The moving selection endpoint and caret.
  public var head: Int

  /// Creates a selection from endpoints.
  public init(anchor: Int = 0, head: Int? = nil) {
    self.anchor = max(0, anchor)
    self.head = max(0, head ?? anchor)
  }

  /// Creates a forward selection from a range.
  public init(_ range: Range<Int>) {
    self.init(anchor: range.lowerBound, head: range.upperBound)
  }

  /// The ordered selection range.
  public var range: Range<Int> {
    min(anchor, head) ..< max(anchor, head)
  }

  /// A value that indicates whether the selection has no range.
  public var isCollapsed: Bool {
    anchor == head
  }

  /// The caret offset.
  public var caret: Int {
    head
  }
}

/// An editing or navigation command for a text editor.
public enum TextEditCommand: Sendable, Hashable {
  /// Inserts text at the selection.
  case insert(String)
  /// Pastes text at the selection.
  case paste(String)
  /// Inserts a newline at the selection.
  case insertNewline
  /// Deletes the selection or preceding character.
  case deleteBackward
  /// Deletes the selection or following character.
  case deleteForward
  /// Moves left, optionally extending the selection.
  case moveLeft(extendingSelection: Bool = false)
  /// Moves right, optionally extending the selection.
  case moveRight(extendingSelection: Bool = false)
  /// Moves up, optionally extending the selection.
  case moveUp(extendingSelection: Bool = false)
  /// Moves down, optionally extending the selection.
  case moveDown(extendingSelection: Bool = false)
  /// Moves to the line start, optionally extending the selection.
  case moveToLineStart(extendingSelection: Bool = false)
  /// Moves to the line end, optionally extending the selection.
  case moveToLineEnd(extendingSelection: Bool = false)
  /// Selects the complete document.
  case selectAll
  /// Submits the document text.
  case submit
}

/// The observable effects of one text editor command.
public struct TextEditorResult: Sendable, Hashable {
  /// A value that indicates whether text changed.
  public var textChanged: Bool
  /// A value that indicates whether selection changed.
  public var selectionChanged: Bool
  /// The submitted text, if the command submitted it.
  public var submittedText: String?

  /// Creates a text editor result.
  public init(textChanged: Bool = false, selectionChanged: Bool = false, submittedText: String? = nil) {
    self.textChanged = textChanged
    self.selectionChanged = selectionChanged
    self.submittedText = submittedText
  }
}

/// A mutable text editor with selection and command handling.
@MainActor
public final class TextEditor {
  /// The semantic identifier.
  public let id: SemanticID
  /// The editable document.
  public var document: TextDocument
  /// The current text selection.
  public var selection: TextSelection
  /// A value that indicates whether editing is enabled.
  public var isEnabled: Bool
  /// A value that indicates whether the editor has focus.
  public var isFocused: Bool
  /// The action invoked when text is submitted.
  public var onSubmit: (@MainActor @Sendable (_ text: String) -> Void)?

  /// Creates a text editor.
  /// - Complexity: O(n), where n is the initial text length.
  public init(
    _ text: String = "",
    id: SemanticID = "text-editor",
    selection: TextSelection? = nil,
    isEnabled: Bool = true,
    onSubmit: (@MainActor @Sendable (_ text: String) -> Void)? = nil
  ) {
    self.id = id
    self.document = TextDocument(text)
    self.selection = selection ?? TextSelection(anchor: document.characterCount)
    self.isEnabled = isEnabled
    self.isFocused = false
    self.onSubmit = onSubmit
    clampSelection()
  }

  /// The currently selected text.
  /// - Complexity: O(n), where n is the document length.
  public var selectedText: String {
    document.string(in: selection.range)
  }

  /// Performs an editing command and reports its effects.
  /// - Complexity: O(n), where n is the document length.
  @discardableResult
  public func perform(_ command: TextEditCommand) -> TextEditorResult {
    guard isEnabled else { return TextEditorResult() }
    let oldDocument = document
    let oldSelection = selection
    var submittedText: String?

    switch command {
    case let .insert(text), let .paste(text):
      replaceSelection(with: text)
    case .insertNewline:
      replaceSelection(with: "\n")
    case .deleteBackward:
      if selection.isCollapsed, selection.caret > 0 {
        document.replace((selection.caret - 1) ..< selection.caret, with: "")
        collapseSelection(at: selection.caret - 1)
      } else if selection.isCollapsed == false {
        replaceSelection(with: "")
      }
    case .deleteForward:
      if selection.isCollapsed, selection.caret < document.characterCount {
        document.replace(selection.caret ..< (selection.caret + 1), with: "")
      } else if selection.isCollapsed == false {
        replaceSelection(with: "")
      }
    case let .moveLeft(extending):
      let target = selection.isCollapsed || extending ? max(0, selection.head - 1) : selection.range.lowerBound
      move(to: target, extendingSelection: extending)
    case let .moveRight(extending):
      let target =
        selection.isCollapsed || extending
          ? min(document.characterCount, selection.head + 1)
          : selection.range.upperBound
      move(to: target, extendingSelection: extending)
    case let .moveUp(extending):
      let location = document.lineAndColumn(at: selection.head)
      move(to: document.offset(line: location.line - 1, column: location.column), extendingSelection: extending)
    case let .moveDown(extending):
      let location = document.lineAndColumn(at: selection.head)
      move(to: document.offset(line: location.line + 1, column: location.column), extendingSelection: extending)
    case let .moveToLineStart(extending):
      let location = document.lineAndColumn(at: selection.head)
      move(to: document.offset(line: location.line, column: 0), extendingSelection: extending)
    case let .moveToLineEnd(extending):
      let location = document.lineAndColumn(at: selection.head)
      move(to: document.offset(line: location.line, column: .max), extendingSelection: extending)
    case .selectAll:
      selection = TextSelection(0 ..< document.characterCount)
    case .submit:
      submittedText = document.text
      onSubmit?(document.text)
    }

    clampSelection()
    return TextEditorResult(
      textChanged: document != oldDocument,
      selectionChanged: selection != oldSelection,
      submittedText: submittedText
    )
  }

  /// Creates the text editor's semantic node.
  /// - Complexity: O(1).
  public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
    var state: SemanticState = []
    if isEnabled == false {
      state.insert(.disabled)
    }
    if isFocused {
      state.insert(.focused)
    }
    return SemanticNode(
      id: id,
      role: .textEditor,
      label: "Text editor",
      value: document.text,
      state: state,
      actions: isEnabled ? [.focus, .setValue, .submit] : [],
      frame: frame
    )
  }

  private func replaceSelection(with replacement: String) {
    let range = selection.range
    let start = range.lowerBound
    let previousCount = document.characterCount
    document.replace(range, with: replacement)
    collapseSelection(at: start + document.characterCount - (previousCount - range.count))
  }

  private func move(to offset: Int, extendingSelection: Bool) {
    let target = min(max(0, offset), document.characterCount)
    selection =
      extendingSelection
        ? TextSelection(anchor: selection.anchor, head: target)
        : TextSelection(anchor: target)
  }

  private func collapseSelection(at offset: Int) {
    selection = TextSelection(anchor: min(max(0, offset), document.characterCount))
  }

  private func clampSelection() {
    selection.anchor = min(selection.anchor, document.characterCount)
    selection.head = min(selection.head, document.characterCount)
  }
}
