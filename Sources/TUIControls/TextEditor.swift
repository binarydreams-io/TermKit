import Foundation
import TUIFoundation

public struct TextDocument: Sendable, Hashable {
    public private(set) var text: String

    public init(_ text: String = "") {
        self.text = Self.normalized(text)
    }

    public var characterCount: Int { text.count }

    public var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    public func string(in range: Range<Int>) -> String {
        let bounds = clamped(range)
        let lower = text.index(text.startIndex, offsetBy: bounds.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: bounds.upperBound)
        return String(text[lower..<upper])
    }

    public mutating func replace(_ range: Range<Int>, with replacement: String) {
        let bounds = clamped(range)
        let lower = text.index(text.startIndex, offsetBy: bounds.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: bounds.upperBound)
        text.replaceSubrange(lower..<upper, with: Self.normalized(replacement))
    }

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

    public func offset(line targetLine: Int, column targetColumn: Int) -> Int {
        let line = max(0, targetLine)
        let column = max(0, targetColumn)
        var currentLine = 0
        var currentColumn = 0
        var offset = 0

        for character in text {
            if currentLine == line, currentColumn == column { return offset }
            if character == "\n" {
                if currentLine == line { return offset }
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
        return lower..<upper
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

public struct TextSelection: Sendable, Hashable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int = 0, head: Int? = nil) {
        self.anchor = max(0, anchor)
        self.head = max(0, head ?? anchor)
    }

    public init(_ range: Range<Int>) {
        self.init(anchor: range.lowerBound, head: range.upperBound)
    }

    public var range: Range<Int> { min(anchor, head)..<max(anchor, head) }
    public var isCollapsed: Bool { anchor == head }
    public var caret: Int { head }
}

public enum TextEditCommand: Sendable, Hashable {
    case insert(String)
    case paste(String)
    case insertNewline
    case deleteBackward
    case deleteForward
    case moveLeft(extendingSelection: Bool = false)
    case moveRight(extendingSelection: Bool = false)
    case moveUp(extendingSelection: Bool = false)
    case moveDown(extendingSelection: Bool = false)
    case moveToLineStart(extendingSelection: Bool = false)
    case moveToLineEnd(extendingSelection: Bool = false)
    case selectAll
    case submit
}

public struct TextEditorResult: Sendable, Hashable {
    public var textChanged: Bool
    public var selectionChanged: Bool
    public var submittedText: String?

    public init(textChanged: Bool = false, selectionChanged: Bool = false, submittedText: String? = nil) {
        self.textChanged = textChanged
        self.selectionChanged = selectionChanged
        self.submittedText = submittedText
    }
}

@MainActor
public final class TextEditor {
    public let id: SemanticID
    public var document: TextDocument
    public var selection: TextSelection
    public var isEnabled: Bool
    public var isFocused: Bool
    public var onSubmit: (@MainActor @Sendable (String) -> Void)?

    public init(
        _ text: String = "",
        id: SemanticID = "text-editor",
        selection: TextSelection? = nil,
        isEnabled: Bool = true,
        onSubmit: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.id = id
        document = TextDocument(text)
        self.selection = selection ?? TextSelection(anchor: document.characterCount)
        self.isEnabled = isEnabled
        isFocused = false
        self.onSubmit = onSubmit
        clampSelection()
    }

    public var selectedText: String {
        document.string(in: selection.range)
    }

    @discardableResult
    public func perform(_ command: TextEditCommand) -> TextEditorResult {
        guard isEnabled else { return TextEditorResult() }
        let oldDocument = document
        let oldSelection = selection
        var submittedText: String?

        switch command {
        case .insert(let text), .paste(let text):
            replaceSelection(with: text)
        case .insertNewline:
            replaceSelection(with: "\n")
        case .deleteBackward:
            if selection.isCollapsed, selection.caret > 0 {
                document.replace((selection.caret - 1)..<selection.caret, with: "")
                collapseSelection(at: selection.caret - 1)
            } else if selection.isCollapsed == false {
                replaceSelection(with: "")
            }
        case .deleteForward:
            if selection.isCollapsed, selection.caret < document.characterCount {
                document.replace(selection.caret..<(selection.caret + 1), with: "")
            } else if selection.isCollapsed == false {
                replaceSelection(with: "")
            }
        case .moveLeft(let extending):
            let target = selection.isCollapsed || extending ? max(0, selection.head - 1) : selection.range.lowerBound
            move(to: target, extendingSelection: extending)
        case .moveRight(let extending):
            let target =
                selection.isCollapsed || extending
                ? min(document.characterCount, selection.head + 1)
                : selection.range.upperBound
            move(to: target, extendingSelection: extending)
        case .moveUp(let extending):
            let location = document.lineAndColumn(at: selection.head)
            move(to: document.offset(line: location.line - 1, column: location.column), extendingSelection: extending)
        case .moveDown(let extending):
            let location = document.lineAndColumn(at: selection.head)
            move(to: document.offset(line: location.line + 1, column: location.column), extendingSelection: extending)
        case .moveToLineStart(let extending):
            let location = document.lineAndColumn(at: selection.head)
            move(to: document.offset(line: location.line, column: 0), extendingSelection: extending)
        case .moveToLineEnd(let extending):
            let location = document.lineAndColumn(at: selection.head)
            move(to: document.offset(line: location.line, column: .max), extendingSelection: extending)
        case .selectAll:
            selection = TextSelection(0..<document.characterCount)
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

    public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
        var state: SemanticState = []
        if isEnabled == false { state.insert(.disabled) }
        if isFocused { state.insert(.focused) }
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
