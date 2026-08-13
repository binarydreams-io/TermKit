import Testing

@testable import TUIAgentUI

struct PresentationStateTests {
    @Test("Reasoning keeps one collapsed row while content streams")
    func reasoningHeight() {
        let short = ReasoningDisclosure(phase: .running, summary: "Inspecting", body: "One line")
        let long = ReasoningDisclosure(phase: .running, summary: "Inspecting", body: String(repeating: "line\n", count: 100))

        #expect(short.collapsedHeight == 1)
        #expect(long.collapsedHeight == 1)
    }

    @Test("Tool rows preserve the icon column in every state", arguments: ToolCallState.allCases)
    func toolIconColumn(state: ToolCallState) {
        let row = ToolCallRow(id: "tool", label: "Read file", state: state, iconColumnWidth: 3)

        #expect(row.labelWidth(in: 20) == 17)
        #expect(row.iconColumnWidth == 3)
    }

    @Test("Failed tools reveal errors only when expanded")
    func toolErrorState() {
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

    @Test("Shell expansion preserves selection and scroll anchor")
    func shellExpansion() {
        var result = ShellResult(
            command: "swift test",
            output: String(repeating: "line\n", count: 12),
            selection: 2..<8,
            scrollAnchorLine: 4
        )

        #expect(result.visibleLineLimit(viewportWidth: 60) == 4)
        result.toggleExpansion()

        #expect(result.visibleLineLimit(viewportWidth: 60) == nil)
        #expect(result.selection == 2..<8)
        #expect(result.scrollAnchorLine == 4)
    }

    @Test("Automatic diff layout changes above 120 columns")
    func diffLayout() {
        let diff = AgentDiffView<String>(input: .unifiedText("@@ -1 +1 @@"))

        #expect(diff.resolvedLayout(availableWidth: 120) == .unified)
        #expect(diff.resolvedLayout(availableWidth: 121) == .sideBySide)
    }

    @Test("Diagnostics summarize the highest actionable severity")
    func diagnostics() {
        let list = DiagnosticsList(
            diagnostics: [
                DiagnosticPresentation(id: 1, severity: .warning, message: "Unused value"),
                DiagnosticPresentation(id: 2, severity: .error, path: "Main.swift", line: 3, message: "Missing return"),
            ],
            mode: .inline
        )

        #expect(list.highestSeverity == .error)
        #expect(list.inlineSummary == "1 error")
    }

    @Test("Todo presentation limits animation to active work")
    func todoState() {
        let active = TodoItem(id: 1, title: "Compile", state: .inProgress)
        let completed = TodoItem(id: 2, title: "Format", state: .completed)

        #expect(active.animatesActivitySymbol)
        #expect(active.usesMutedText == false)
        #expect(completed.animatesActivitySymbol == false)
        #expect(completed.usesMutedText)
    }
}
