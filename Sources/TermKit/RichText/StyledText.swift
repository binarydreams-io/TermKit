/// A half-open UTF-8 byte range in text.
public struct TextRange: Sendable, Hashable {
    /// The inclusive lower bound.
    public let lowerBound: Int
    /// The exclusive upper bound.
    public let upperBound: Int

    /// Creates a range from its lower and upper bounds.
    public init(_ lowerBound: Int, _ upperBound: Int) {
        precondition(lowerBound >= 0 && upperBound >= lowerBound)
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    /// The number of bytes represented by the range.
    /// - Complexity: O(1).
    public var count: Int { upperBound - lowerBound }
    /// A Boolean value that indicates whether the range contains no bytes.
    /// - Complexity: O(1).
    public var isEmpty: Bool { lowerBound == upperBound }

    /// Returns whether this range overlaps another range.
    /// - Complexity: O(1).
    public func intersects(_ other: TextRange) -> Bool {
        lowerBound < other.upperBound && other.lowerBound < upperBound
    }

    /// Returns the smallest range that contains both ranges.
    /// - Complexity: O(1).
    public func union(_ other: TextRange) -> TextRange {
        TextRange(Swift.min(lowerBound, other.lowerBound), Swift.max(upperBound, other.upperBound))
    }
}

/// A semantic role used to style text independently of concrete colors.
public enum SemanticTextRole: Sendable, Hashable {
    /// Regular body text.
    case body
    /// A heading at the associated level.
    case heading(Int)
    /// Link text.
    case link
    /// Inline code text.
    case inlineCode
    /// Code text.
    case code
    /// A language keyword.
    case keyword
    /// A string literal.
    case string
    /// A numeric literal.
    case number
    /// A source-code comment.
    case comment
    /// A type name.
    case type
    /// A list marker.
    case listMarker
    /// A block-quote marker.
    case quoteMarker
    /// A table header.
    case tableHeader
    /// Added diff text.
    case diffAdded
    /// Removed diff text.
    case diffRemoved
    /// Unchanged diff text.
    case diffContext
    /// A diff hunk header.
    case diffHunk
    /// A line number.
    case lineNumber
    /// Deemphasized text.
    case muted
    /// Diagnostic text.
    case diagnostic
}

/// Semantic attributes that modify styled text.
public struct StyledTextAttributes: OptionSet, Sendable, Hashable {
    /// The raw attribute bit mask.
    public let rawValue: UInt16

    /// Creates attributes from a raw bit mask.
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// Bold text.
    public static let bold = StyledTextAttributes(rawValue: 1 << 0)
    /// Italic text.
    public static let italic = StyledTextAttributes(rawValue: 1 << 1)
    /// Underlined text.
    public static let underline = StyledTextAttributes(rawValue: 1 << 2)
    /// Struck-through text.
    public static let strikethrough = StyledTextAttributes(rawValue: 1 << 3)
    /// Dimmed text.
    public static let dim = StyledTextAttributes(rawValue: 1 << 4)
    /// Selected text.
    public static let selected = StyledTextAttributes(rawValue: 1 << 5)
}

/// A contiguous text span with uniform semantic styling.
public struct StyledTextSpan: Sendable, Hashable {
    /// The text in the span.
    public let text: String
    /// The semantic role of the span.
    public let role: SemanticTextRole
    /// The attributes applied to the span.
    public let attributes: StyledTextAttributes
    /// The link destination associated with the span.
    public let link: String?

    /// Creates a styled text span.
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

/// Text composed of normalized semantic spans.
public struct StyledText: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The normalized spans that compose the text.
    public let spans: [StyledTextSpan]

    /// Creates styled text with one semantic role.
    public init(_ text: String = "", role: SemanticTextRole = .body) {
        spans = text.isEmpty ? [] : [StyledTextSpan(text, role: role)]
    }

    /// Creates styled text and merges adjacent spans with identical styling.
    /// - Complexity: O(*n*), where *n* is the total text length of the spans.
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

    /// Creates styled text from a string literal.
    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// The text with all semantic styling removed.
    /// - Complexity: O(*n*), where *n* is the total text length.
    public var plainText: String {
        spans.map(\.text).joined()
    }

    /// The terminal column width of the plain text.
    /// - Complexity: O(*n*), where *n* is the number of graphemes.
    public var cellWidth: Int {
        TerminalWidth.width(of: plainText)
    }

    /// Returns text formed by appending and normalizing another value.
    /// - Complexity: O(*n* + *m*), where the terms are the span text lengths.
    public func appending(_ other: StyledText) -> StyledText {
        StyledText(spans: spans + other.spans)
    }

    /// Returns text with the specified role, attributes, and link applied to each span.
    /// - Complexity: O(*n*), where *n* is the total text length.
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

/// A policy for wrapping styled text into terminal rows.
public enum TextWrapPolicy: Sendable, Hashable {
    /// Preserves explicit line breaks without width-based wrapping.
    case none
    /// Wraps at grapheme boundaries.
    case character
    /// Prefers whitespace boundaries and falls back to grapheme boundaries.
    case word
}

/// One measured line of styled text.
public struct StyledTextLine: Sendable, Hashable {
    /// The styled line content.
    public let text: StyledText
    /// The terminal column width of the line.
    public let cellWidth: Int

    /// Creates a measured styled-text line.
    public init(text: StyledText, cellWidth: Int? = nil) {
        self.text = text
        self.cellWidth = cellWidth ?? text.cellWidth
    }
}

extension StyledText {
    /// Splits the text into lines that fit the specified terminal width.
    /// - Complexity: O(*n*), where *n* is the number of graphemes.
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
                    width: TerminalWidth.width(of: character),
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
