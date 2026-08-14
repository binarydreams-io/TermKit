import Testing

@testable import TermKit

struct ANSIEncoderTests {
    @Test("Monochrome mode emits attributes without color SGR codes")
    func monochromeMode() throws {
        var graphemes = GraphemeInterner()
        var styles = StyleInterner()
        let glyph = try graphemes.intern("▀")
        let style = try styles.intern(
            CellStyle(
                foreground: .rgba(.white),
                background: .rgba(.black),
                attributes: .bold
            )
        )
        var encoder = ANSIEncoder(colorMode: .monochrome)

        let bytes = try encoder.encode(
            [.setStyle(style), .write(graphemeID: glyph, displayWidth: 1, flags: [])],
            graphemes: graphemes,
            styles: styles
        )
        let output = String(decoding: bytes, as: UTF8.self)

        #expect(output.contains("\u{1B}[0;1m"))
        #expect(output.contains("38;") == false)
        #expect(output.contains("48;") == false)
        #expect(output.contains("▀"))
    }
    @Test func trueColorEncodingFramesSynchronizedOutput() throws {
        var graphemes = GraphemeInterner()
        let letter = try graphemes.intern("A")
        var styles = StyleInterner()
        let style = try styles.intern(
            CellStyle(
                foreground: .rgba(RGBA(redByte: 1, greenByte: 2, blueByte: 3)),
                attributes: .bold
            )
        )
        let operations: [SemanticOperation] = [
            .moveCursor(to: CellPoint(x: 2, y: 1)),
            .setStyle(style),
            .write(graphemeID: letter, displayWidth: 1, flags: []),
        ]
        var encoder = ANSIEncoder(colorMode: .trueColor)

        let bytes = try encoder.encode(operations, graphemes: graphemes, styles: styles, synchronizedOutput: true)

        #expect(String(decoding: bytes, as: UTF8.self) == "\u{1b}[?2026h\u{1b}[2;3H\u{1b}[0;1;38;2;1;2;3mA\u{1b}[?2026l")
        #expect(encoder.cursor == CellPoint(x: 3, y: 1))
        #expect(encoder.activeStyleID == style)
    }

    @Test func encoderOmitsRedundantCursorAndStyleSequences() throws {
        var graphemes = GraphemeInterner()
        let first = try graphemes.intern("a")
        let second = try graphemes.intern("b")
        let styles = StyleInterner()
        let operations: [SemanticOperation] = [
            .moveCursor(to: .zero),
            .setStyle(.default),
            .write(graphemeID: first, displayWidth: 1, flags: []),
            .moveCursor(to: CellPoint(x: 1, y: 0)),
            .setStyle(.default),
            .write(graphemeID: second, displayWidth: 1, flags: []),
        ]
        var encoder = ANSIEncoder()

        let output = try encoder.encode(operations, graphemes: graphemes, styles: styles)

        #expect(String(decoding: output, as: UTF8.self) == "\u{1b}[1;1H\u{1b}[0mab")
    }

    @Test(arguments: [
        (ANSIColorMode.indexed256, "\u{1b}[0;38;5;196m"),
        (ANSIColorMode.ansi16, "\u{1b}[0;91m"),
    ])
    func fallbackColorModes(mode: ANSIColorMode, expected: String) throws {
        var graphemes = GraphemeInterner()
        let letter = try graphemes.intern("x")
        var styles = StyleInterner()
        let style = try styles.intern(CellStyle(foreground: .rgba(RGBA(redByte: 255, greenByte: 0, blueByte: 0))))
        var encoder = ANSIEncoder(colorMode: mode)

        let output = try encoder.encode(
            [.setStyle(style), .write(graphemeID: letter, displayWidth: 1, flags: [])],
            graphemes: graphemes,
            styles: styles
        )

        #expect(String(decoding: output, as: UTF8.self) == expected + "x")
    }

    @Test func failedEncodingDoesNotCommitEncoderState() throws {
        let graphemes = GraphemeInterner()
        let styles = StyleInterner()
        var encoder = ANSIEncoder()

        #expect(throws: ANSIEncoderError.unknownGrapheme(GraphemeID(rawValue: 9))) {
            try encoder.encode(
                [.moveCursor(to: CellPoint(x: 2, y: 2)), .write(graphemeID: GraphemeID(rawValue: 9), displayWidth: 1, flags: [])],
                graphemes: graphemes,
                styles: styles
            )
        }
        #expect(encoder.cursor == nil)
        #expect(encoder.activeStyleID == nil)
    }

    @Test func emptyDiffDoesNotEmitSyncFrame() throws {
        var encoder = ANSIEncoder()

        let output = try encoder.encode(
            [SemanticOperation](),
            graphemes: GraphemeInterner(),
            styles: StyleInterner(),
            synchronizedOutput: true
        )

        #expect(output.isEmpty)
    }
}
