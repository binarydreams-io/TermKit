import Testing
@testable import TUITerminal

struct InputParserTests {
    @Test("UTF-8 keys preserve fragmented scalars")
    func fragmentedUTF8Key() {
        var parser = TerminalInputParser()
        let bytes = Array("é".utf8)

        #expect(parser.append([bytes[0]]) == TerminalInputParserOutput())
        #expect(parser.append([bytes[1]]).events == [.key(TerminalKeyEvent(key: .text("é")))])
    }

    @Test("Invalid UTF-8 is reported and parsing continues")
    func invalidUTF8Recovers() {
        var parser = TerminalInputParser()
        let output = parser.append([0xFF, 0x61])

        #expect(output.errors == [.invalidUTF8([0xFF])])
        #expect(output.events == [.key(TerminalKeyEvent(key: .text("a")))])
    }

    @Test("Escape deadline resolves a standalone Escape key")
    func standaloneEscape() {
        var parser = TerminalInputParser()

        #expect(parser.append([0x1B]).events.isEmpty)
        #expect(parser.resolveAmbiguousEscape().events == [.key(TerminalKeyEvent(key: .escape))])
    }

    @Test("CSI and SS3 keys parse with modifiers")
    func escapeKeys() {
        var parser = TerminalInputParser()
        let output = parser.append(Array("\u{1B}[1;5A\u{1B}OP".utf8))

        #expect(
            output.events == [
                .key(TerminalKeyEvent(key: .up, modifiers: .control)),
                .key(TerminalKeyEvent(key: .function(1))),
            ]
        )
    }

    @Test("Bracketed paste stays one event across chunks")
    func bracketedPaste() {
        var parser = TerminalInputParser()

        #expect(parser.append(Array("\u{1B}[200~hello".utf8)).events.isEmpty)
        #expect(parser.append(Array("\nworld\u{1B}[201~".utf8)).events == [.paste("hello\nworld")])
    }

    @Test("Oversized paste is discarded through its end marker")
    func oversizedPasteRecovers() {
        var parser = TerminalInputParser(
            configuration: TerminalInputParserConfiguration(maximumPasteByteCount: 4)
        )

        let output = parser.append(Array("\u{1B}[200~12345\u{1B}[201~a".utf8))

        #expect(output.errors == [.pasteTooLarge(limit: 4)])
        #expect(output.events == [.key(TerminalKeyEvent(key: .text("a")))])
    }

    @Test("SGR mouse reports zero-based coordinates and modifiers")
    func sgrMouse() {
        var parser = TerminalInputParser()

        let output = parser.append(Array("\u{1B}[<20;8;4M".utf8))

        #expect(
            output.events == [
                .mouse(
                    TerminalMouseEvent(
                        action: .press(.left),
                        position: TerminalCellPoint(column: 7, row: 3),
                        modifiers: [.shift, .control]
                    )
                )
            ]
        )
    }

    @Test("Focus events parse independently")
    func focusEvents() {
        var parser = TerminalInputParser()

        #expect(parser.append(Array("\u{1B}[I\u{1B}[O".utf8)).events == [.focus(.gained), .focus(.lost)])
    }

    @Test("Kitty keyboard is opt-in")
    func kittyKeyboardIsOptIn() {
        var disabledParser = TerminalInputParser()
        var enabledParser = TerminalInputParser(
            configuration: TerminalInputParserConfiguration(enablesKittyKeyboard: true)
        )
        let sequence = Array("\u{1B}[97;5:2u".utf8)

        #expect(disabledParser.append(sequence).errors == [.unknownEscapeSequence(sequence)])
        #expect(
            enabledParser.append(sequence).events == [
                .key(TerminalKeyEvent(key: .text("a"), modifiers: .control, action: .repeat))
            ]
        )
    }

    @Test("Incomplete input is typed at end of stream")
    func finishReportsIncompleteInput() {
        var parser = TerminalInputParser()
        let bytes = Array("\u{1B}[1;".utf8)
        _ = parser.append(bytes)

        #expect(parser.finish().errors == [.incompleteSequence(bytes)])
    }
}
