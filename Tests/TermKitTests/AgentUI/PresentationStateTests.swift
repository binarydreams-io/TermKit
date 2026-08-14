@testable import TermKit
import Testing

struct PresentationStateTests {
  @Test
  func `Reasoning keeps one collapsed row while content streams`() {
    let short = ReasoningDisclosure(phase: .running, body: "One line", summary: "Inspecting")
    let long = ReasoningDisclosure(phase: .running, body: String(repeating: "line\n", count: 100), summary: "Inspecting")

    #expect(short.collapsedHeight == 1)
    #expect(long.collapsedHeight == 1)
  }

  @Test(arguments: ToolCallState.allCases)
  func `Tool rows preserve the icon column in every state`(state: ToolCallState) {
    let row = ToolCallRow(id: "tool", label: "Read file", state: state, iconColumnWidth: 3)

    #expect(row.labelWidth(in: 20) == 17)
    #expect(row.iconColumnWidth == 3)
  }

  @Test
  func `Failed tools reveal errors only when expanded`() {
    let collapsed = ToolCallRow(id: 1, label: "Build", state: .failed, errorBody: "Compiler error")
    let expanded = ToolCallRow(
      id: 1,
      label: "Build",
      state: .failed,
      errorBody: "Compiler error",
      isErrorExpanded: true
    )

    #expect(collapsed.revealsError == false)
    #expect(expanded.revealsError)
  }

  @Test
  func `Shell expansion preserves selection and scroll anchor`() {
    var result = ShellResult(
      command: "swift test",
      output: String(repeating: "line\n", count: 12),
      selection: 2 ..< 8,
      scrollAnchorLine: 4
    )

    #expect(result.visibleLineLimit(viewportWidth: 60) == 4)
    result.toggleExpansion()

    #expect(result.visibleLineLimit(viewportWidth: 60) == nil)
    #expect(result.selection == 2 ..< 8)
    #expect(result.scrollAnchorLine == 4)
  }

  @Test
  func `Automatic diff layout changes above 120 columns`() {
    let diff = AgentDiffView<String>(input: .unifiedText("@@ -1 +1 @@"))

    #expect(diff.resolvedLayout(availableWidth: 120) == .unified)
    #expect(diff.resolvedLayout(availableWidth: 121) == .sideBySide)
  }

  @Test
  func `Diagnostics summarize the highest actionable severity`() {
    let list = DiagnosticsList(
      diagnostics: [
        DiagnosticPresentation(id: 1, severity: .warning, message: "Unused value"),
        DiagnosticPresentation(id: 2, severity: .error, message: "Missing return", path: "Main.swift", line: 3)
      ],
      mode: .inline
    )

    #expect(list.highestSeverity == .error)
    #expect(list.inlineSummary == "1 error")
  }

  @Test
  func `Todo presentation limits animation to active work`() {
    let active = TodoItem(id: 1, title: "Compile", state: .inProgress)
    let completed = TodoItem(id: 2, title: "Format", state: .completed)

    #expect(active.animatesActivitySymbol)
    #expect(active.usesMutedText == false)
    #expect(completed.animatesActivitySymbol == false)
    #expect(completed.usesMutedText)
  }
}
