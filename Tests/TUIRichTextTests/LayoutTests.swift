import TUIRichText
import Testing

@Suite("Rich-text layouts")
struct RichTextLayoutTests {
    @Test("Code block lays out title, line numbers, wrapping, copy, and selection")
    func codeBlockLayout() {
        let model = CodeBlockModel(
            code: "123456789",
            language: "text",
            title: "Example",
            showsLineNumbers: true,
            wrapPolicy: .character,
            selection: TextRange(0, 3)
        )

        let result = CodeBlockLayout().layout(model, width: 8, highlighter: PlainSyntaxHighlighter())

        #expect(result.size.width == 8)
        #expect(result.size.height == 3)
        #expect(result.title?.plainText == "Example")
        #expect(result.gutterWidth == 3)
        #expect(result.contentWidth == 5)
        #expect(result.rows.map { $0.content.plainText } == ["12345", "6789"])
        #expect(result.rows.map(\.lineNumber) == [1, nil])
        #expect(result.rows.map(\.isContinuation) == [false, true])
        #expect(result.copyText == "123")
        #expect(result.selection == TextRange(0, 3))
    }

    @Test("Code block can disable copy and selection")
    func disabledCodeActions() {
        let model = CodeBlockModel(code: "value", isCopyEnabled: false, isSelectable: false, selection: TextRange(0, 2))
        let result = CodeBlockLayout().layout(model, width: 10)

        #expect(result.copyText == nil)
        #expect(result.selection == nil)
    }

    @Test("Code block reserves content space on a narrow layout")
    func narrowCodeBlock() {
        let model = CodeBlockModel(code: "界", showsLineNumbers: true, wrapPolicy: .character)
        let result = CodeBlockLayout().layout(model, width: 1)

        #expect(result.gutterWidth == 0)
        #expect(result.contentWidth == 1)
        #expect(result.gutterWidth + result.contentWidth == result.size.width)
    }

    @Test("Automatic diff layout switches only above 120 columns")
    func automaticDiffMode() {
        let view = DiffView(model: DiffViewModel(unifiedDiff: sampleDiff))

        #expect(view.layout(width: 120).mode == .unified)
        #expect(view.layout(width: 121).mode == .sideBySide)
    }

    @Test("Explicit diff layout policy overrides terminal width")
    func explicitDiffMode() {
        let narrow = DiffView(
            model: DiffViewModel(unifiedDiff: sampleDiff, layoutPolicy: .sideBySide)
        )
        let wide = DiffView(
            model: DiffViewModel(unifiedDiff: sampleDiff, layoutPolicy: .unified)
        )

        #expect(narrow.layout(width: 60).mode == .sideBySide)
        #expect(wide.layout(width: 160).mode == .unified)
    }

    @Test("Side-by-side layout pairs removals and additions")
    func pairedDiffRows() {
        let result = DiffView(model: DiffViewModel(unifiedDiff: sampleDiff)).layout(width: 121)
        let pairs = result.rows.compactMap { row -> (DiffPaneLine?, DiffPaneLine?)? in
            guard case .sideBySide(let left, let right) = row else { return nil }
            return (left, right)
        }

        #expect(pairs.count == 3)
        #expect(pairs[0].0?.content.plainText == "same")
        #expect(pairs[0].1?.content.plainText == "same")
        #expect(pairs[1].0?.content.plainText == "old")
        #expect(pairs[1].1?.content.plainText == "new")
        #expect(pairs[2].0?.content.plainText == "tail")
        #expect(pairs[2].1?.content.plainText == "tail")
    }

    private let sampleDiff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,3 @@
         same
        -old
        +new
         tail
        """
}
