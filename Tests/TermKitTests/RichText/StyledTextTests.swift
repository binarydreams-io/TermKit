import Testing

@testable import TermKit

@Suite("Styled text and terminal width")
struct StyledTextTests {
    @Test(
        "Terminal width handles Unicode clusters",
        arguments: [
            ("ASCII", 5),
            ("e\u{301}", 1),
            ("\u{301}", 0),
            ("界", 2),
            ("❤️", 2),
            ("👩‍💻", 2),
            ("👨‍👩‍👧‍👦", 2),
            ("🇺🇦", 2),
            ("1️⃣", 2),
        ]
    )
    func unicodeWidth(value: String, expected: Int) {
        #expect(TerminalWidth.width(of: value) == expected)
    }

    @Test("Wrapping preserves grapheme boundaries and links")
    func wrappingPreservesSemantics() {
        let text = StyledText(
            spans: [
                StyledTextSpan("A"),
                StyledTextSpan("界B", role: .link, attributes: .underline, link: "https://example.test"),
            ]
        )

        let lines = text.wrapped(to: 2, policy: .character)

        #expect(lines.map { $0.text.plainText } == ["A", "界", "B"])
        #expect(lines.map(\.cellWidth) == [1, 2, 1])
        #expect(lines[1].text.spans[0].link == "https://example.test")
        #expect(lines[1].text.spans[0].attributes.contains(.underline))
    }

    @Test("Word wrapping uses whitespace without carrying it to the next row")
    func wordWrapping() {
        let lines = StyledText("hello world").wrapped(to: 8, policy: .word)

        #expect(lines.map { $0.text.plainText } == ["hello", "world"])
    }

    @Test("Cell-grid renderer reserves a continuation cell for wide graphemes")
    func semanticCellGrid() {
        let text = StyledText(
            spans: [StyledTextSpan("界x", role: .link, link: "target")]
        )

        let grid = StyledTextCellRenderer().render(text, width: 3, wrapPolicy: .character)

        #expect(grid.height == 1)
        #expect(grid.rows[0][0]?.grapheme == "界")
        #expect(grid.rows[0][0]?.displayWidth == 2)
        #expect(grid.rows[0][0]?.link == "target")
        #expect(grid.rows[0][1]?.isContinuation == true)
        #expect(grid.rows[0][2]?.grapheme == "x")
    }

    @Test("A one-cell grid uses a visible fallback for a wide grapheme")
    func narrowSemanticCellGrid() {
        let grid = StyledTextCellRenderer().render(StyledText("界"), width: 1, wrapPolicy: .character)

        #expect(grid.rows[0][0]?.grapheme == "�")
        #expect(grid.rows[0][0]?.displayWidth == 1)
        #expect(grid.rows[0][0]?.isContinuation == false)
    }
}
