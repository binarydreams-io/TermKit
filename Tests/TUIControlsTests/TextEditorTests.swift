import Testing

@testable import TUIControls

@MainActor
struct TextEditorTests {
    @Test("Paste replaces the selected range and preserves line breaks")
    func pasteReplacesSelection() {
        let editor = TextEditor("alpha beta", selection: TextSelection(6..<10))

        let result = editor.perform(.paste("one\ntwo"))

        #expect(editor.document.text == "alpha one\ntwo")
        #expect(editor.selection == TextSelection(anchor: 13))
        #expect(result.textChanged)
    }

    @Test("Newline editing and submit are separate commands")
    func newlineDoesNotSubmit() {
        let recorder = SubmitRecorder()
        let editor = TextEditor("hello", onSubmit: { text in recorder.values.append(text) })

        let newline = editor.perform(.insertNewline)
        let submit = editor.perform(.submit)

        #expect(editor.document.text == "hello\n")
        #expect(newline.submittedText == nil)
        #expect(submit.submittedText == "hello\n")
        #expect(recorder.values == ["hello\n"])
    }

    @Test("Vertical movement clamps the column to each target line")
    func verticalMovement() {
        let editor = TextEditor("abcd\nx\nwxyz", selection: TextSelection(anchor: 3))

        editor.perform(.moveDown())
        #expect(editor.selection.caret == 6)

        editor.perform(.moveDown())
        #expect(editor.selection.caret == 8)
    }

    @Test("Documents normalize CRLF and CR line endings")
    func normalizedLineEndings() {
        var document = TextDocument("one\r\ntwo\rthree")

        #expect(document.text == "one\ntwo\nthree")
        #expect(document.lines.map(String.init) == ["one", "two", "three"])
        #expect(document.lineAndColumn(at: 8) == (line: 2, column: 0))

        document.replace(3..<4, with: "\r\n")
        #expect(document.text == "one\ntwo\nthree")
    }
}

@MainActor
private final class SubmitRecorder {
    var values: [String] = []
}
