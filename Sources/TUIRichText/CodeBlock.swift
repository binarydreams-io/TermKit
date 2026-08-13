import TUIFoundation

public struct CodeBlockModel: Sendable, Hashable {
    public let code: String
    public let language: String?
    public let title: String?
    public let showsLineNumbers: Bool
    public let wrapPolicy: TextWrapPolicy
    public let isCopyEnabled: Bool
    public let isSelectable: Bool
    public let selection: TextRange?

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

    public var copyText: String? {
        guard isCopyEnabled else { return nil }
        guard let selection, isSelectable else { return code }
        let bytes = Array(code.utf8)
        guard isUTF8Boundary(selection.lowerBound, in: bytes), isUTF8Boundary(selection.upperBound, in: bytes) else { return code }
        return String(decoding: bytes[selection.lowerBound..<selection.upperBound], as: UTF8.self)
    }
}

public struct CodeBlockCopyAction: Sendable {
    private let action: @Sendable (String) -> Void

    public init(_ action: @escaping @Sendable (String) -> Void) {
        self.action = action
    }

    public func callAsFunction(for model: CodeBlockModel) {
        if let text = model.copyText { action(text) }
    }
}

public struct CodeBlockRow: Sendable, Hashable {
    public let lineNumber: Int?
    public let isContinuation: Bool
    public let content: StyledText
    public let cellWidth: Int

    public init(lineNumber: Int?, isContinuation: Bool, content: StyledText) {
        self.lineNumber = lineNumber
        self.isContinuation = isContinuation
        self.content = content
        cellWidth = content.cellWidth
    }
}

public struct CodeBlockLayoutResult: Sendable, Hashable {
    public let size: CellSize
    public let title: StyledText?
    public let gutterWidth: Int
    public let contentWidth: Int
    public let rows: [CodeBlockRow]
    public let selection: TextRange?
    public let copyText: String?

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

public struct CodeBlockLayout: Sendable {
    public init() {}

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
