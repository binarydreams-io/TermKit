/// The content and display options for a code block.
public struct CodeBlockModel: Sendable, Hashable {
  /// The source code.
  public let code: String
  /// The optional language identifier.
  public let language: String?
  /// The optional title.
  public let title: String?
  /// A Boolean value that controls line-number display.
  public let showsLineNumbers: Bool
  /// The policy used to wrap code lines.
  public let wrapPolicy: TextWrapPolicy
  /// A Boolean value that enables copying.
  public let isCopyEnabled: Bool
  /// A Boolean value that enables selection.
  public let isSelectable: Bool
  /// The selected UTF-8 byte range.
  public let selection: TextRange?

  /// Creates a code-block model.
  public init(
    code: String,
    language: String? = nil,
    title: String? = nil,
    showsLineNumbers: Bool = false,
    wrapPolicy: TextWrapPolicy = .none,
    isCopyEnabled: Bool = true,
    isSelectable: Bool = true,
    selection: TextRange? = nil
  ) {
    precondition(selection?.upperBound ?? 0 <= code.utf8.count)
    self.code = code
    self.language = language
    self.title = title
    self.showsLineNumbers = showsLineNumbers
    self.wrapPolicy = wrapPolicy
    self.isCopyEnabled = isCopyEnabled
    self.isSelectable = isSelectable
    self.selection = selection
  }

  /// The selected text, complete code, or `nil` when copying is disabled.
  /// - Complexity: O(*n*), where *n* is the UTF-8 byte count of `code`.
  public var copyText: String? {
    guard isCopyEnabled else { return nil }
    guard let selection, isSelectable else { return code }
    let bytes = Array(code.utf8)
    guard isUTF8Boundary(selection.lowerBound, in: bytes), isUTF8Boundary(selection.upperBound, in: bytes) else { return code }
    return String(decoding: bytes[selection.lowerBound ..< selection.upperBound], as: UTF8.self)
  }
}

/// A callable action that copies text from a code-block model.
public struct CodeBlockCopyAction: Sendable {
  private let action: @Sendable (String) -> Void

  /// Creates a copy action from a text consumer.
  public init(_ action: @escaping @Sendable (_ text: String) -> Void) {
    self.action = action
  }

  /// Invokes the action with the model's copyable text.
  /// - Complexity: O(*n*), where *n* is the UTF-8 byte count of the model's code.
  public func callAsFunction(for model: CodeBlockModel) {
    if let text = model.copyText {
      action(text)
    }
  }
}

/// One visual row in a code-block layout.
public struct CodeBlockRow: Sendable, Hashable {
  /// The logical line number shown for the row.
  public let lineNumber: Int?
  /// A Boolean value that indicates whether the row continues a logical line.
  public let isContinuation: Bool
  /// The styled row content.
  public let content: StyledText
  /// The terminal column width of the content.
  public let cellWidth: Int

  /// Creates a code-block row.
  public init(lineNumber: Int?, isContinuation: Bool, content: StyledText) {
    self.lineNumber = lineNumber
    self.isContinuation = isContinuation
    self.content = content
    self.cellWidth = content.cellWidth
  }
}

/// The measured rows and metadata of a code-block layout.
public struct CodeBlockLayoutResult: Sendable, Hashable {
  /// The total layout size.
  public let size: CellSize
  /// The styled title, if present.
  public let title: StyledText?
  /// The width of the line-number gutter.
  public let gutterWidth: Int
  /// The width available for code content.
  public let contentWidth: Int
  /// The visual code rows.
  public let rows: [CodeBlockRow]
  /// The active UTF-8 selection range.
  public let selection: TextRange?
  /// The text available to a copy action.
  public let copyText: String?

  /// Creates a code-block layout result.
  public init(
    size: CellSize,
    title: StyledText?,
    gutterWidth: Int,
    contentWidth: Int,
    rows: [CodeBlockRow],
    selection: TextRange?,
    copyText: String?
  ) {
    self.size = size
    self.title = title
    self.gutterWidth = gutterWidth
    self.contentWidth = contentWidth
    self.rows = rows
    self.selection = selection
    self.copyText = copyText
  }
}

/// A layout engine for code-block models.
public struct CodeBlockLayout: Sendable {
  /// Creates a code-block layout engine.
  public init() {}

  /// Measures and wraps a code-block model at the specified width.
  /// - Complexity: O(*n*), where *n* is the number of graphemes in the code.
  public func layout(
    _ model: CodeBlockModel,
    width: Int,
    highlighter: any SyntaxHighlighter = SubtleSyntaxHighlighter(),
    changedRanges: [TextRange] = []
  ) -> CodeBlockLayoutResult {
    precondition(width > 0)
    let highlighted = highlighter.highlight(model.code, language: model.language, changedRanges: changedRanges)
    let logicalLines = highlighted.text.wrapped(to: Swift.max(1, highlighted.text.cellWidth), policy: .none)
    let lineCount = Swift.max(1, logicalLines.count)
    let desiredGutterWidth = model.showsLineNumbers ? String(lineCount).count + 2 : 0
    let gutterWidth = Swift.min(desiredGutterWidth, Swift.max(0, width - 1))
    let contentWidth = Swift.max(1, width - gutterWidth)
    var rows: [CodeBlockRow] = []

    for (index, logicalLine) in logicalLines.enumerated() {
      let wrapped = logicalLine.text.wrapped(to: contentWidth, policy: model.wrapPolicy)
      for (segmentIndex, segment) in wrapped.enumerated() {
        rows.append(
          CodeBlockRow(
            lineNumber: model.showsLineNumbers && segmentIndex == 0 ? index + 1 : nil,
            isContinuation: segmentIndex > 0,
            content: segment.text
          )
        )
      }
    }
    let title = model.title.map { StyledText($0, role: .muted) }
    return CodeBlockLayoutResult(
      size: CellSize(width: width, height: rows.count + (title == nil ? 0 : 1)),
      title: title,
      gutterWidth: gutterWidth,
      contentWidth: contentWidth,
      rows: rows,
      selection: model.isSelectable ? model.selection : nil,
      copyText: model.copyText
    )
  }
}
