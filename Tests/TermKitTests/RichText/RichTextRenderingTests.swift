import Testing

@testable import TermKit

@Suite("Theme-aware rich-text rendering")
struct RichTextRenderingTests {
    @Test("Rich-text leaf measures, retains its primitive, and paints wide cells")
    @MainActor
    func richTextLeaf() throws {
        let richText = RichText(StyledText("界x"), scheme: .light)
        let descriptor = try #require(richText.graphBody.first)
        var surface = Surface(size: CellSize(width: 4, height: 1))
        var resources = ControlRenderResources()

        let semantics = try richText.paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds, origin: CellPoint(x: 1)),
            resources: &resources
        )

        #expect(descriptor.primitive(as: RichText.self) == richText)
        #expect(richText.sizeThatFits(ProposedCellSize(width: 2)) == CellSize(width: 2, height: 2))
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 1)].graphemeID) == "界")
        #expect(surface[CellPoint(x: 1)].displayWidth == 2)
        #expect(surface[CellPoint(x: 2)].isContinuation)
        #expect(semantics.frame == CellRect(x: 1, y: 0, width: 3, height: 1))
        try surface.validateWideCells()
    }

    @Test("Styled text resolves semantic colors and packs wide cells for both schemes")
    func styledTextThemesAndPacking() throws {
        let text = StyledText(spans: [
            StyledTextSpan("界", role: .link, attributes: .underline, link: "target"),
            StyledTextSpan("x", role: .keyword),
        ])
        let dark = try RichTextRenderer(scheme: .dark).render(text, width: 4, wrapPolicy: .character)
        let light = try RichTextRenderer(scheme: .light).render(text, width: 4, wrapPolicy: .character)

        #expect(dark.cells.rows[0][0].grapheme == "界")
        #expect(dark.cells.rows[0][0].packedCell.displayWidth == 2)
        #expect(dark.cells.rows[0][1].packedCell.isContinuation)
        #expect(dark.cells.rows[0][0].link == "target")
        #expect(dark.cells.rows[0][0].style.attributes.contains(.underline))
        #expect(dark.cells.rows[0][0].style.foreground != light.cells.rows[0][0].style.foreground)
        #expect(dark.graphemes.value(for: dark.surface[.zero].graphemeID) == "界")
        try dark.surface.validateWideCells()
    }

    @Test("Markdown paints semantic constructs and code backgrounds")
    func markdownPresentationCells() throws {
        let source = """
            # Title

            - [site](https://example.test)

            ```swift
            let value = 7
            ```
            """
        let rendered = try MarkdownPresentation(source).render(width: 20, scheme: .dark)
        let cells = rendered.cells.rows.flatMap { $0 }

        #expect(cells.contains { $0.grapheme == "T" && $0.role == .heading(1) && $0.style.attributes.contains(.bold) })
        #expect(cells.contains { $0.grapheme == "s" && $0.role == .link && $0.link == "https://example.test" })
        #expect(cells.contains { $0.grapheme == "•" && $0.role == .listMarker })
        #expect(cells.contains { $0.grapheme == "l" && $0.role == .keyword })
        #expect(cells.contains { $0.role == .keyword && $0.style.background != rendered.cells.rows[0][0].style.background })
        #expect(rendered.surface.size.width == 20)
    }

    @Test("Malformed Markdown uses source text and attaches a diagnostic")
    func malformedMarkdownFallback() throws {
        let source = "```swift\nlet value = 1"
        let rendered = try MarkdownPresentation(source).render(width: 12, scheme: .light)

        #expect(rendered.diagnostics.map(\.message) == ["Unclosed fenced code block"])
        #expect(rowText(rendered, row: 0).hasPrefix("```swift"))
        #expect(rendered.cells.rows.flatMap { $0 }.filter { $0.grapheme != " " }.allSatisfy { $0.role == .body })
        #expect(rendered.semantics.children.first?.role == .status)
    }

    @Test("Malformed Markdown preserves semantic prefix blocks")
    func malformedMarkdownPreservesSemanticPrefix() throws {
        let source = "# Stable\n\nParagraph with **strong**.\n\n```swift\nlet value = 1"
        let rendered = try MarkdownPresentation(source).render(width: 24, scheme: .light)
        let cells = rendered.cells.rows.flatMap { $0 }

        #expect(cells.contains { $0.grapheme == "S" && $0.role == .heading(1) })
        #expect(cells.contains { $0.grapheme == "s" && $0.style.attributes.contains(.bold) })
        #expect(cells.contains { $0.grapheme == "`" && $0.role == .body })
        #expect(cells.contains { $0.grapheme == "l" && $0.role == .keyword } == false)
        #expect(rendered.diagnostics.map(\.message) == ["Unclosed fenced code block"])
    }

    @Test("Code block paints title, gutter, syntax, selection, and semantic state")
    func codeBlockCells() throws {
        let model = CodeBlockModel(
            code: "let value = 7",
            language: "swift",
            title: "Example",
            showsLineNumbers: true,
            wrapPolicy: .character,
            selection: TextRange(4, 9)
        )
        let rendered = try CodeBlock(model: model).render(width: 12, scheme: .dark)

        #expect(rowText(rendered, row: 0).hasPrefix("Example"))
        #expect(rendered.cells.rows[1].contains { $0.grapheme == "1" && $0.role == .lineNumber })
        #expect(rendered.cells.rows.flatMap { $0 }.contains { $0.role == .keyword })
        #expect(rendered.cells.rows.flatMap { $0 }.contains { $0.isSelected })
        #expect(rendered.semantics.state.contains(.selected))
        #expect(rendered.semantics.role == .textEditor)
        #expect(rendered.surface.size.width == 12)
    }

    @Test("Unified and side-by-side diffs paint gutters and semantic backgrounds")
    func diffCellsAtRepresentativeWidths() throws {
        let source = """
            --- a/file.txt
            +++ b/file.txt
            @@ -1,2 +1,2 @@
             same
            -old
            +new
            """
        let view = DiffView(model: DiffViewModel(unifiedDiff: source))
        let narrow = try view.render(width: 40, scheme: .light)
        let wide = try view.render(width: 121, scheme: .dark)
        let narrowCells = narrow.cells.rows.flatMap { $0 }
        let wideCells = wide.cells.rows.flatMap { $0 }

        #expect(narrowCells.contains { $0.grapheme == "o" && $0.role == .diffRemoved })
        #expect(narrowCells.contains { $0.grapheme == "n" && $0.role == .diffAdded })
        #expect(narrowCells.contains { $0.role == .lineNumber && $0.grapheme == "1" })
        #expect(
            narrowCells.first { $0.role == .diffRemoved }?.style.background != narrowCells.first { $0.role == .diffAdded }?.style.background
        )
        #expect(wideCells.contains { $0.grapheme == "│" })
        #expect(wide.surface.size.width == 121)
        #expect(wide.semantics.role == .textEditor)
    }

    @Test("Malformed diff renders original plain text with diagnostics")
    func malformedDiffFallback() throws {
        let source = "not a diff\nstill text"
        let rendered = try DiffView(model: DiffViewModel(unifiedDiff: source)).render(width: 16, scheme: .dark)

        #expect(rowText(rendered, row: 0).hasPrefix("not a diff"))
        #expect(rowText(rendered, row: 1).hasPrefix("still text"))
        #expect(rendered.cells.rows.flatMap { $0 }.filter { $0.grapheme != " " }.allSatisfy { $0.role == .body })
        #expect(rendered.diagnostics.map(\.message) == ["Line 1: Input is not a recognized unified diff"])
    }

    private func rowText(_ result: RichTextRenderResult, row: Int) -> String {
        result.cells.rows[row].filter { $0.isContinuation == false }.map(\.grapheme).joined()
    }
}
