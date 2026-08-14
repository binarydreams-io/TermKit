import Testing

@testable import TermKit

@Suite("Streaming Markdown")
struct MarkdownTests {
    @Test("Parser recognizes the supported block and inline constructs")
    func supportedSubset() throws {
        let source = """
            # Head *em*

            Paragraph with **strong**, __also strong__, [link](https://example.test), and `code`.

            - one
            - two

            1. first
            2. second

            > quoted
            > words

            ---

            | Name | Value |
            | :--- | ---: |
            | A | 1 |

            ```swift
            let x = 1
            ```
            """

        let document = MarkdownParser().parse(source)

        #expect(document.blocks.count == 8)
        #expect(document.diagnostics.isEmpty)

        guard case .heading(let level, let heading) = document.blocks[0].kind else {
            Issue.record("Expected a heading")
            return
        }
        #expect(level == 1)
        #expect(heading.plainText == "Head em")
        #expect(heading.spans.contains { $0.text == "em" && $0.attributes.contains(.italic) })

        guard case .paragraph(let paragraph) = document.blocks[1].kind else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(paragraph.spans.contains { $0.text == "strong" && $0.attributes.contains(.bold) })
        #expect(paragraph.spans.contains { $0.text == "also strong" && $0.attributes.contains(.bold) })
        #expect(paragraph.spans.contains { $0.text == "link" && $0.link == "https://example.test" })
        #expect(paragraph.spans.contains { $0.text == "code" && $0.role == .inlineCode })

        guard case .unorderedList(let unordered) = document.blocks[2].kind,
            case .orderedList(let ordered) = document.blocks[3].kind,
            case .blockQuote(let quote) = document.blocks[4].kind,
            case .horizontalRule = document.blocks[5].kind,
            case .table(let table) = document.blocks[6].kind,
            case .codeFence(let fence) = document.blocks[7].kind
        else {
            Issue.record("Expected all supported block types")
            return
        }
        #expect(unordered.map { $0.content.plainText } == ["one", "two"])
        #expect(ordered.map(\.ordinal) == [1, 2])
        #expect(quote.plainText == "quoted\nwords")
        #expect(table.headers.map(\.plainText) == ["Name", "Value"])
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.rows[0].map(\.plainText) == ["A", "1"])
        #expect(fence.language == "swift")
        #expect(fence.code == "let x = 1")
        #expect(fence.isClosed)
    }

    @Test("Incomplete inline constructs remain literal")
    func incompleteInlineIsConservative() throws {
        let source = "A **strong *tail and [link](destination"
        let document = MarkdownParser().parse(source)
        let block = try #require(document.blocks.first)
        guard case .paragraph(let paragraph) = block.kind else {
            Issue.record("Expected a paragraph")
            return
        }

        #expect(paragraph.plainText == source)
        #expect(paragraph.spans.allSatisfy { $0.attributes.isEmpty && $0.link == nil })
    }

    @Test("Changing a block marker reparses an adjacent preceding block")
    func boundaryChangeReparsesPreviousBlock() throws {
        let source = "first\n# second"
        let previous = MarkdownParser().parse(source)
        let markerOffset = "first\n".utf8.count

        let result = try MarkdownParser().reparseTail(
            of: previous,
            replacing: TextRange(markerOffset, markerOffset + 2),
            with: ""
        )

        #expect(result.reparsedRange.lowerBound == 0)
        #expect(result.document.blocks.count == 1)
        guard case .paragraph(let paragraph) = try #require(result.document.blocks.first).kind else {
            Issue.record("Expected the adjacent lines to merge into a paragraph")
            return
        }
        #expect(paragraph.plainText == "first second")
    }

    @Test("Incomplete fence is retained with a diagnostic")
    func incompleteFence() throws {
        let document = MarkdownParser().parse("```swift\nlet x = 1")
        let block = try #require(document.blocks.first)
        guard case .codeFence(let fence) = block.kind else {
            Issue.record("Expected a code fence")
            return
        }

        #expect(fence.code == "let x = 1")
        #expect(fence.isClosed == false)
        #expect(document.diagnostics.count == 1)
    }

    @Test("Appending content reparses only the affected tail")
    func affectedTailReparse() throws {
        var parser = StreamingMarkdownParser(source: "# Stable\n\nA **bo")
        let stableHeading = try #require(parser.document.blocks.first)

        let result = try parser.append("ld**")

        #expect(result.reparsedRange.lowerBound == "# Stable\n\n".utf8.count)
        #expect(result.document.blocks.first == stableHeading)
        guard case .paragraph(let paragraph) = try #require(result.document.blocks.last).kind else {
            Issue.record("Expected the reparsed paragraph")
            return
        }
        #expect(paragraph.plainText == "A bold")
        #expect(paragraph.spans.contains { $0.text == "bold" && $0.attributes.contains(.bold) })
    }

    @Test("Appending after a blank line preserves all stable blocks")
    func appendNewBlock() throws {
        let initial = "# Stable\n\nfirst\n\n"
        var parser = StreamingMarkdownParser(source: initial)
        let stableBlocks = parser.document.blocks

        let result = try parser.append("- item")

        #expect(result.reparsedRange == TextRange(initial.utf8.count, result.document.source.utf8.count))
        #expect(Array(result.document.blocks.prefix(2)) == stableBlocks)
        guard case .unorderedList(let items) = try #require(result.document.blocks.last).kind else {
            Issue.record("Expected an appended list")
            return
        }
        #expect(items.first?.content.plainText == "item")
    }

    @Test("Parser and streaming updates normalize CRLF and CR line endings")
    func normalizedLineEndings() throws {
        let document = MarkdownParser().parse("# Head\r\n\r\nfirst\rsecond")

        #expect(document.source == "# Head\n\nfirst\nsecond")
        guard case .paragraph(let paragraph) = try #require(document.blocks.last).kind else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(paragraph.plainText == "first second")

        var streaming = StreamingMarkdownParser(source: "# Head\r\n")
        _ = try streaming.append("\rnext")
        #expect(streaming.document.source == "# Head\n\nnext")
    }
}
