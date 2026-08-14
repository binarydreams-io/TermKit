/// A semantic syntax token at a UTF-8 byte range.
public struct SyntaxHighlightSpan: Sendable, Hashable {
    /// The UTF-8 byte range of the token.
    public let range: TextRange
    /// The semantic role assigned to the token.
    public let role: SemanticTextRole

    /// Creates a syntax-highlight span.
    public init(range: TextRange, role: SemanticTextRole) {
        self.range = range
        self.role = role
    }
}

/// The styled text and token metadata produced by a syntax highlighter.
public struct SyntaxHighlightResult: Sendable, Hashable {
    /// The highlighted text.
    public let text: StyledText
    /// The recognized syntax tokens.
    public let spans: [SyntaxHighlightSpan]
    /// The UTF-8 byte ranges invalidated by the highlight operation.
    public let changedRanges: [TextRange]

    /// Creates a syntax-highlight result.
    public init(text: StyledText, spans: [SyntaxHighlightSpan], changedRanges: [TextRange]) {
        self.text = text
        self.spans = spans
        self.changedRanges = changedRanges
    }
}

/// A type that applies semantic syntax roles to source text.
public protocol SyntaxHighlighter: Sendable {
    /// Highlights source text and reports the ranges affected by the update.
    /// - Complexity: O(*n*), where *n* is the UTF-8 byte count of `text`.
    func highlight(_ text: String, language: String?, changedRanges: [TextRange]) -> SyntaxHighlightResult
}

/// A highlighter that assigns the code role to all text.
public struct PlainSyntaxHighlighter: SyntaxHighlighter, Sendable {
    /// Creates a plain syntax highlighter.
    public init() {}

    /// Assigns the code role to the complete source text.
    /// - Complexity: O(*n*), where *n* is the UTF-8 byte count of `text`.
    public func highlight(_ text: String, language: String?, changedRanges: [TextRange] = []) -> SyntaxHighlightResult {
        let fullRange = TextRange(0, text.utf8.count)
        return SyntaxHighlightResult(
            text: StyledText(text, role: .code),
            spans: text.isEmpty ? [] : [SyntaxHighlightSpan(range: fullRange, role: .code)],
            changedRanges: changedRanges.isEmpty ? [fullRange] : changedRanges
        )
    }
}

/// A lightweight highlighter for common comments, literals, keywords, and type names.
public struct SubtleSyntaxHighlighter: SyntaxHighlighter, Sendable {
    /// Creates a subtle syntax highlighter.
    public init() {}

    /// Highlights recognized tokens and expands changed ranges to line boundaries.
    /// - Complexity: O(*n*), where *n* is the UTF-8 byte count of `text`.
    public func highlight(_ text: String, language: String?, changedRanges: [TextRange] = []) -> SyntaxHighlightResult {
        let bytes = Array(text.utf8)
        let tokens = tokens(in: bytes, language: language?.lowercased())
        var spans: [StyledTextSpan] = []
        var semanticSpans: [SyntaxHighlightSpan] = []
        var position = 0

        for token in tokens {
            if position < token.range.lowerBound {
                spans.append(
                    StyledTextSpan(
                        String(decoding: bytes[position..<token.range.lowerBound], as: UTF8.self),
                        role: .code
                    )
                )
            }
            spans.append(
                StyledTextSpan(
                    String(decoding: bytes[token.range.lowerBound..<token.range.upperBound], as: UTF8.self),
                    role: token.role
                )
            )
            semanticSpans.append(token)
            position = token.range.upperBound
        }
        if position < bytes.count {
            spans.append(StyledTextSpan(String(decoding: bytes[position...], as: UTF8.self), role: .code))
        }

        let invalidated = expandedLineRanges(changedRanges, in: bytes)
        return SyntaxHighlightResult(
            text: StyledText(spans: spans),
            spans: semanticSpans,
            changedRanges: invalidated
        )
    }

    private func tokens(in bytes: [UInt8], language: String?) -> [SyntaxHighlightSpan] {
        let hashComments = ["python", "py", "ruby", "rb", "shell", "sh", "bash", "yaml", "yml"].contains(language ?? "")
        let keywords: Set<String> = [
            "actor", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "do",
            "else", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "init", "let",
            "nil", "null", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throw",
            "throws", "true", "try", "var", "while",
        ]
        var result: [SyntaxHighlightSpan] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2F {
                let end = lineEnd(in: bytes, from: index)
                result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .comment))
                index = end
                continue
            }
            if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2A {
                var end = index + 2
                while end + 1 < bytes.count && (bytes[end] != 0x2A || bytes[end + 1] != 0x2F) { end += 1 }
                end = end + 1 < bytes.count ? end + 2 : bytes.count
                result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .comment))
                index = end
                continue
            }
            if hashComments, byte == 0x23 {
                let end = lineEnd(in: bytes, from: index)
                result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .comment))
                index = end
                continue
            }
            if byte == 0x22 || byte == 0x27 {
                let quote = byte
                var end = index + 1
                var escaped = false
                while end < bytes.count {
                    if escaped {
                        escaped = false
                    } else if bytes[end] == 0x5C {
                        escaped = true
                    } else if bytes[end] == quote {
                        end += 1
                        break
                    }
                    end += 1
                }
                result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .string))
                index = end
                continue
            }
            if isDigit(byte) {
                var end = index + 1
                while end < bytes.count && (isDigit(bytes[end]) || bytes[end] == 0x2E || bytes[end] == 0x5F) { end += 1 }
                result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .number))
                index = end
                continue
            }
            if isIdentifierStart(byte) {
                var end = index + 1
                while end < bytes.count && isIdentifierContinuation(bytes[end]) { end += 1 }
                let word = String(decoding: bytes[index..<end], as: UTF8.self)
                if keywords.contains(word) {
                    result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .keyword))
                } else if byte >= 0x41 && byte <= 0x5A {
                    result.append(SyntaxHighlightSpan(range: TextRange(index, end), role: .type))
                }
                index = end
                continue
            }
            index += scalarLength(startingWith: byte)
        }
        return result
    }

    private func expandedLineRanges(_ ranges: [TextRange], in bytes: [UInt8]) -> [TextRange] {
        if ranges.isEmpty { return [TextRange(0, bytes.count)] }
        var expanded: [TextRange] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let clippedLower = Swift.min(range.lowerBound, bytes.count)
            let clippedUpper = Swift.min(range.upperBound, bytes.count)
            var lower = clippedLower
            while lower > 0 && bytes[lower - 1] != 0x0A { lower -= 1 }
            var upper = clippedUpper
            while upper < bytes.count && bytes[upper] != 0x0A { upper += 1 }
            if upper < bytes.count { upper += 1 }
            let candidate = TextRange(lower, upper)
            if let last = expanded.last, last.upperBound >= candidate.lowerBound {
                expanded[expanded.count - 1] = last.union(candidate)
            } else {
                expanded.append(candidate)
            }
        }
        return expanded
    }

    private func lineEnd(in bytes: [UInt8], from index: Int) -> Int {
        bytes[index...].firstIndex(of: 0x0A) ?? bytes.count
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private func isIdentifierStart(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
    }

    private func isIdentifierContinuation(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || isDigit(byte)
    }

    private func scalarLength(startingWith byte: UInt8) -> Int {
        if byte < 0x80 { return 1 }
        if byte < 0xE0 { return 2 }
        if byte < 0xF0 { return 3 }
        return 4
    }
}
