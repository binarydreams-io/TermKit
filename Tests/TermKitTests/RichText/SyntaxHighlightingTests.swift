@testable import TermKit
import Testing

@Suite("Syntax highlighting")
struct SyntaxHighlightingTests {
  @Test
  func `Subtle highlighter recognizes common lexical tokens`() {
    let source = "let value = \"Ada\" // name\nreturn 42"
    let result = SubtleSyntaxHighlighter().highlight(source, language: "swift", changedRanges: [])

    #expect(texts(for: .keyword, in: result, source: source) == ["let", "return"])
    #expect(texts(for: .string, in: result, source: source) == ["\"Ada\""])
    #expect(texts(for: .comment, in: result, source: source) == ["// name"])
    #expect(texts(for: .number, in: result, source: source) == ["42"])
    #expect(result.text.plainText == source)
  }

  @Test
  func `Changed ranges expand to complete lines`() throws {
    let source = "let first = 1\nlet second = 2\n"
    let bytes = Array(source.utf8)
    let firstLineEnd = try #require(bytes.firstIndex(of: 0x0A)) + 1
    let result = SubtleSyntaxHighlighter().highlight(
      source,
      language: "swift",
      changedRanges: [TextRange(firstLineEnd + 4, firstLineEnd + 7), TextRange(5, 8)]
    )

    #expect(result.changedRanges == [TextRange(0, bytes.count)])
  }

  @Test
  func `Plain highlighter preserves readable code`() {
    let source = "unknown syntax"
    let result = PlainSyntaxHighlighter().highlight(source, language: nil, changedRanges: [])

    #expect(result.text == StyledText(source, role: .code))
    #expect(result.spans == [SyntaxHighlightSpan(range: TextRange(0, source.utf8.count), role: .code)])
  }

  private func texts(
    for role: SemanticTextRole,
    in result: SyntaxHighlightResult,
    source: String
  ) -> [String] {
    let bytes = Array(source.utf8)
    return result.spans.filter { $0.role == role }.map {
      String(decoding: bytes[$0.range.lowerBound ..< $0.range.upperBound], as: UTF8.self)
    }
  }
}
