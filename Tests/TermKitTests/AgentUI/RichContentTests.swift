@testable import TermKit
import Testing

struct AgentRichContentTests {
  @Test
  @MainActor
  func `Code block wrapper forwards presentation, selection, copy, wrap, and highlighting`() throws {
    var copiedText: String?
    let source = "let value = 7"
    let view = AgentCodeBlockView(
      AgentCodeBlock(
        text: source,
        language: "swift",
        title: "Example",
        showsLineNumbers: true,
        selection: 4 ..< 9,
        wrapPolicy: .wrap
      ),
      actions: CodeBlockActions { copiedText = $0 },
      highlighter: TestSyntaxHighlighter()
    )

    let output = try view.render(in: AgentRenderContext(width: 12, scheme: .dark))
    let activated = view.activate()

    #expect(output.plainText.split(separator: "\n").first?.hasPrefix("Example") == true)
    #expect(output.cells.rows.flatMap(\.self).compactMap(\.self).contains { $0.role == .lineNumber })
    #expect(output.cells.rows.flatMap(\.self).compactMap(\.self).contains { $0.role == .type })
    #expect(output.cells.rows.flatMap(\.self).compactMap(\.self).contains { $0.attributes.contains(.selected) })
    #expect(output.semantics.role == .textEditor)
    #expect(output.semantics.actions.contains(.activate))
    #expect(activated)
    #expect(copiedText == "value")
  }

  @Test
  @MainActor
  func `Code block can disable selection and copy`() throws {
    let view = AgentCodeBlockView(
      AgentCodeBlock(text: "value", supportsSelection: false, selection: 0 ..< 5, isCopyEnabled: false)
    )

    let output = try view.render(in: AgentRenderContext(width: 10, scheme: .light))

    #expect(output.semantics.role == .text)
    #expect(output.semantics.actions.isEmpty)
    #expect(view.codeBlock.richTextModel.copyText == nil)
    #expect(view.activate() == false)
  }

  @Test
  @MainActor
  func `Unified diff text uses width policy and semantic regions`() throws {
    let source = """
    --- a/file.txt
    +++ b/file.txt
    @@ -1,2 +1,2 @@
     same
    -old
    +new
    """
    let view = AgentDiffContentView(unifiedDiff: source)
    let narrow = try view.render(in: AgentRenderContext(width: 40, scheme: .light))
    let wide = try view.render(in: AgentRenderContext(width: 121, scheme: .dark))
    let narrowCells = narrow.cells.rows.flatMap(\.self).compactMap(\.self)

    #expect(view.diffView.resolvedLayout(availableWidth: 40) == .unified)
    #expect(view.diffView.resolvedLayout(availableWidth: 121) == .sideBySide)
    #expect(narrowCells.contains { $0.role == .diffAdded })
    #expect(narrowCells.contains { $0.role == .diffRemoved })
    #expect(narrowCells.contains { $0.role == .diffContext })
    #expect(narrowCells.contains { $0.role == .diffHunk })
    #expect(narrowCells.contains { $0.role == .lineNumber })
    #expect(wide.plainText.contains("│"))
    #expect(narrow.semantics.role == .textEditor)
  }

  @Test
  @MainActor
  func `Parsed diff honors explicit layout, wrap, and selection policies`() throws {
    let parsed = UnifiedDiff(
      files: [
        DiffFile(
          oldPath: "old.swift",
          newPath: "new.swift",
          hunks: [
            DiffHunk(
              oldStart: 1,
              oldCount: 1,
              newStart: 1,
              newCount: 1,
              lines: [
                DiffLine(kind: .removal, content: "old value", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(kind: .addition, content: "new value", oldLineNumber: nil, newLineNumber: 1)
              ]
            )
          ]
        )
      ]
    )
    let view = AgentDiffContentView(
      diff: parsed,
      layoutPolicy: .sideBySide,
      supportsSelection: false,
      wrapPolicy: .wrap
    )

    let output = try view.render(in: AgentRenderContext(width: 30, scheme: .dark))

    #expect(view.diffView.richTextModel.diff == parsed)
    #expect(view.diffView.resolvedLayout(availableWidth: 30) == .sideBySide)
    #expect(output.plainText.contains("│"))
    #expect(output.semantics.role == .text)
  }
}

private struct TestSyntaxHighlighter: SyntaxHighlighter {
  func highlight(_ text: String, language: String?, changedRanges: [TextRange]) -> SyntaxHighlightResult {
    let role: SemanticTextRole = language == "swift" ? .type : .code
    let range = TextRange(0, text.utf8.count)
    return SyntaxHighlightResult(
      text: StyledText(text, role: role),
      spans: text.isEmpty ? [] : [SyntaxHighlightSpan(range: range, role: role)],
      changedRanges: changedRanges
    )
  }
}
