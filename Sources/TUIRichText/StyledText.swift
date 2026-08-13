import TUIFoundation

public struct TextRange: Sendable, Hashable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(_ lowerBound: Int, _ upperBound: Int) {
        precondition(lowerBound >= 0 && upperBound >= lowerBound)
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var count: Int { upperBound - lowerBound }
    public var isEmpty: Bool { lowerBound == upperBound }

    public func intersects(_ other: TextRange) -> Bool {
        lowerBound < other.upperBound && other.lowerBound < upperBound
    }

    public func union(_ other: TextRange) -> TextRange {
        TextRange(Swift.min(lowerBound, other.lowerBound), Swift.max(upperBound, other.upperBound))
    }
}

public enum SemanticTextRole: Sendable, Hashable {
    case body
    case heading(Int)
    case link
    case inlineCode
    case code
    case keyword
    case string
    case number
    case comment
    case type
    case listMarker
    case quoteMarker
    case tableHeader
    case diffAdded
    case diffRemoved
    case diffContext
    case diffHunk
    case lineNumber
    case muted
    case diagnostic
}

public struct StyledTextAttributes: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let bold = StyledTextAttributes(rawValue: 1 << 0)
    public static let italic = StyledTextAttributes(rawValue: 1 << 1)
    public static let underline = StyledTextAttributes(rawValue: 1 << 2)
    public static let strikethrough = StyledTextAttributes(rawValue: 1 << 3)
    public static let dim = StyledTextAttributes(rawValue: 1 << 4)
    public static let selected = StyledTextAttributes(rawValue: 1 << 5)
}

public struct StyledTextSpan: Sendable, Hashable {
    public let text: String
    public let role: SemanticTextRole
    public let attributes: StyledTextAttributes
    public let link: String?

    public init(
        _ text: String,
        role: SemanticTextRole = .body,
        attributes: StyledTextAttributes = [],
        link: String? = nil
    ) {
        self.text = text
        self.role = role
        self.attributes = attributes
        self.link = link
    }
}

public struct StyledText: Sendable, Hashable, ExpressibleByStringLiteral {
    public let spans: [StyledTextSpan]

    public init(_ text: String = "", role: SemanticTextRole = .body) {
        spans = text.isEmpty ? [] : [StyledTextSpan(text, role: role)]
    }

    public init(spans: [StyledTextSpan]) {
        var normalized: [StyledTextSpan] = []
        for span in spans where span.text.isEmpty == false {
            if let last = normalized.last,
                last.role == span.role,
                last.attributes == span.attributes,
                last.link == span.link
            {
                normalized[normalized.count - 1] = StyledTextSpan(
                    last.text + span.text,
                    role: span.role,
                    attributes: span.attributes,
                    link: span.link
                )
            } else {
                normalized.append(span)
            }
        }
        self.spans = normalized
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var plainText: String {
        spans.map(\.text).joined()
    }

    public var cellWidth: Int {
        TUIFoundation.TerminalWidth.width(of: plainText)
    }

    public func appending(_ other: StyledText) -> StyledText {
        StyledText(spans: spans + other.spans)
    }

    public func applying(
        role: SemanticTextRole? = nil,
        attributes: StyledTextAttributes = [],
        link: String? = nil
    ) -> StyledText {
        StyledText(
            spans: spans.map { span in
                StyledTextSpan(
                    span.text,
                    role: role ?? span.role,
                    attributes: span.attributes.union(attributes),
                    link: link ?? span.link
                )
            }
        )
    }
}

public enum TextWrapPolicy: Sendable, Hashable {
    case none
    case character
    case word
}

public struct StyledTextLine: Sendable, Hashable {
    public let text: StyledText
    public let cellWidth: Int

    public init(text: StyledText, cellWidth: Int? = nil) {
        self.text = text
        self.cellWidth = cellWidth ?? text.cellWidth
    }
}

extension StyledText {
    public func wrapped(to width: Int, policy: TextWrapPolicy = .word) -> [StyledTextLine] {
        precondition(width > 0)
        let atoms = styledAtoms()
        if policy == .none {
            return explicitLines(from: atoms)
        }

        var result: [StyledTextLine] = []
        var line: [StyledAtom] = []
        var lineWidth = 0

        func emit(_ atoms: [StyledAtom], into result: inout [StyledTextLine]) {
            result.append(StyledTextLine(text: StyledText(atoms: atoms)))
        }

        for atom in atoms {
            if atom.grapheme == "\n" {
                emit(line, into: &result)
                line = []
                lineWidth = 0
                continue
            }

            if atom.isBreakableWhitespace && line.isEmpty == false && lineWidth + atom.width > width {
                emit(line, into: &result)
                line = []
                lineWidth = 0
                continue
            }

            if atom.width > 0 && line.isEmpty == false && lineWidth + atom.width > width {
                if policy == .word,
                    let breakIndex = line.lastIndex(where: { $0.isBreakableWhitespace })
                {
                    emit(Array(line[..<breakIndex]), into: &result)
                    line = Array(line[line.index(after: breakIndex)...])
                    while line.first?.isBreakableWhitespace == true {
                        line.removeFirst()
                    }
                    lineWidth = line.reduce(0) { $0 + $1.width }
                    if line.isEmpty == false && lineWidth + atom.width > width {
                        emit(line, into: &result)
                        line = []
                        lineWidth = 0
                    }
                } else {
                    emit(line, into: &result)
                    line = []
                    lineWidth = 0
                }
            }

            if line.isEmpty && atom.isBreakableWhitespace && result.isEmpty == false {
                continue
            }
            line.append(atom)
            lineWidth += atom.width
        }

        if line.isEmpty == false || atoms.last?.grapheme == "\n" || result.isEmpty {
            emit(line, into: &result)
        }
        return result
    }

    fileprivate init(atoms: [StyledAtom]) {
        self.init(
            spans: atoms.map {
                StyledTextSpan($0.grapheme, role: $0.role, attributes: $0.attributes, link: $0.link)
            }
        )
    }

    fileprivate func styledAtoms() -> [StyledAtom] {
        spans.flatMap { span in
            span.text.map { character in
                StyledAtom(
                    grapheme: String(character),
                    width: TUIFoundation.TerminalWidth.width(of: character),
                    role: span.role,
                    attributes: span.attributes,
                    link: span.link
                )
            }
        }
    }

    private func explicitLines(from atoms: [StyledAtom]) -> [StyledTextLine] {
        var lines: [StyledTextLine] = []
        var line: [StyledAtom] = []
        for atom in atoms {
            if atom.grapheme == "\n" {
                lines.append(StyledTextLine(text: StyledText(atoms: line)))
                line = []
            } else {
                line.append(atom)
            }
        }
        if line.isEmpty == false || atoms.last?.grapheme == "\n" || lines.isEmpty {
            lines.append(StyledTextLine(text: StyledText(atoms: line)))
        }
        return lines
    }
}

private struct StyledAtom {
    let grapheme: String
    let width: Int
    let role: SemanticTextRole
    let attributes: StyledTextAttributes
    let link: String?

    var isBreakableWhitespace: Bool {
        grapheme == " " || grapheme == "\t"
    }
}

func isUTF8Boundary(_ offset: Int, in bytes: [UInt8]) -> Bool {
    guard offset >= 0 && offset <= bytes.count else { return false }
    return offset == 0 || offset == bytes.count || bytes[offset] & 0b1100_0000 != 0b1000_0000
}
