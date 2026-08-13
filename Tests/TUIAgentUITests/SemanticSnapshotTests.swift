import Foundation
import Testing
import TUIControls
import TUIDesign
import TUIFoundation
import TUIRichText

@testable import TUIAgentUI

struct SemanticSnapshotTests {
    static let widths = [40, 80, 120, 180]
    static let schemes: [ColorScheme] = [.light, .dark]

    @Test("Agent components match semantic snapshots", arguments: widths, schemes)
    @MainActor
    func componentSnapshots(width: Int, scheme: ColorScheme) throws {
        let context = try AgentRenderContext(
            width: width,
            scheme: scheme,
            elapsed: .milliseconds(600),
            reduceMotion: false
        )
        let source = Self.matrixSnapshot(
            width: width,
            scheme: scheme,
            entries: Self.canonicalComponents().map { ($0, $1.render(in: context)) }
        )
        let key = "\(scheme == .light ? "light" : "dark")-\(width)"

        try Self.record(source, named: key)

        let expected = try Self.snapshot(named: key)

        #expect(source == expected, "Semantic snapshot mismatch: \(key).snap")
    }

    @Test("Interactive states match semantic snapshots", arguments: widths, schemes)
    @MainActor
    func interactiveStateSnapshots(width: Int, scheme: ColorScheme) throws {
        let source = Self.matrixSnapshot(
            width: width,
            scheme: scheme,
            entries: try Self.interactiveStates(width: width, scheme: scheme)
        )
        let key = "states-\(scheme == .light ? "light" : "dark")-\(width)"

        try Self.record(source, named: key)

        let expected = try Self.snapshot(named: key)

        #expect(source == expected, "Semantic snapshot mismatch: \(key).snap")
    }

    @Test("Semantic snapshot preserves sparse cell and tree data")
    func serializationContract() throws {
        let theme = try SemanticTheme.standard.resolve(scheme: .dark)
        let grid = SemanticCellGrid(width: 3, rows: [[
            SemanticCell(grapheme: "界", displayWidth: 2, role: .link, attributes: [.bold, .underline],
                         link: "https://example.test"),
            SemanticCell(grapheme: "", displayWidth: 0, role: .link, attributes: [.bold, .underline],
                         link: "https://example.test", isContinuation: true),
            nil,
        ]])
        let output = AgentRenderOutput(
            cells: grid,
            semantics: SemanticNode(id: "root", role: .group, label: "A\nB", state: [.focused, .selected],
                                    actions: [.dismiss, .activate], frame: CellRect(x: 0, y: 0, width: 3, height: 1),
                                    children: [SemanticNode(id: "child", role: .text, label: "Example")]),
            theme: theme
        )

        #expect(output.semanticSnapshot.contains("grid width=3 height=1"))
        #expect(output.semanticSnapshot.contains(
            "cell x=0 y=0 grapheme=\"界\" width=2 role=link attributes=5 "
                + "link=\"https://example.test\" continuation=0"
        ))
        #expect(output.semanticSnapshot.contains(
            "cell x=1 y=0 grapheme=\"\" width=0 role=link attributes=5 "
                + "link=\"https://example.test\" continuation=1"
        ))
        #expect(output.semanticSnapshot.contains(
            "node path=0 id=\"root\" role=group label=\"A\\nB\" value=null state=9 "
                + "actions=[activate,dismiss] frame=0,0,3,1"
        ))
        #expect(output.semanticSnapshot.contains("node path=0.0 id=\"child\""))
    }

    private static func snapshot(named name: String) throws -> String {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "snap",
            subdirectory: "Snapshots"
        ))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func record(_ snapshot: String, named name: String) throws {
        guard ProcessInfo.processInfo.environment["SWIFTTUI_RECORD_SNAPSHOTS"] == "1" else { return }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Snapshots")
        try snapshot.write(to: directory.appendingPathComponent("\(name).snap"), atomically: true, encoding: .utf8)
    }

    private static func compact(_ snapshot: String) -> String {
        struct CellRun {
            var startX: Int
            var endX: Int
            var y: Int
            var escapedText: String
            var style: Int
        }

        var result: [String] = []
        var run: CellRun?
        var styles: [String: Int] = [:]
        var styleLines: [String] = []

        func appendRun() {
            guard let run else { return }
            result.append(
                "cells x=\(run.startX)..<\(run.endX) y=\(run.y) text=\"\(run.escapedText)\" style=\(run.style)"
            )
        }

        for line in snapshot.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("cell x="),
                  let yRange = line.range(of: " y="),
                  let graphemeRange = line.range(of: " grapheme=\"", range: yRange.upperBound..<line.endIndex),
                  let metadataRange = line.range(of: "\" width=", range: graphemeRange.upperBound..<line.endIndex),
                  let x = Int(line[line.index(line.startIndex, offsetBy: 7)..<yRange.lowerBound]),
                  let y = Int(line[yRange.upperBound..<graphemeRange.lowerBound])
            else {
                appendRun()
                run = nil
                result.append(String(line))
                continue
            }

            let escapedGrapheme = String(line[graphemeRange.upperBound..<metadataRange.lowerBound])
            let metadata = "width=" + line[metadataRange.upperBound...]
            let style = styles[String(metadata)] ?? {
                let style = styles.count
                styles[String(metadata)] = style
                styleLines.append("style \(style) \(metadata)")
                return style
            }()
            if run?.endX == x, run?.y == y, run?.style == style {
                run?.endX += 1
                run?.escapedText += escapedGrapheme
            } else {
                appendRun()
                run = CellRun(startX: x, endX: x + 1, y: y, escapedText: escapedGrapheme, style: style)
            }
        }
        appendRun()
        let gridIndex = result.firstIndex { $0.hasPrefix("grid ") }.map { $0 + 1 } ?? 0
        result.insert(contentsOf: styleLines, at: gridIndex)
        return result.joined(separator: "\n")
    }

    private static func matrixSnapshot(
        width: Int,
        scheme: ColorScheme,
        entries: [(String, AgentRenderOutput)]
    ) -> String {
        var lines = [
            "agent-ui-semantic-matrix-v1",
            "width=\(width) scheme=\(scheme == .light ? "light" : "dark")",
        ]
        if let first = entries.first {
            lines.append(contentsOf: first.1.semanticSnapshot.split(separator: "\n").lazy
                .filter { $0.hasPrefix("color ") }.map(String.init))
        }
        for (name, output) in entries {
            lines.append("component \(name)")
            lines.append(contentsOf: compact(output.semanticSnapshot).split(separator: "\n").lazy
                .filter {
                    !$0.hasPrefix("agent-render-snapshot-")
                        && !$0.hasPrefix("theme ")
                        && !$0.hasPrefix("color ")
                }.map(String.init))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func canonicalComponents() -> [(String, any AgentComponentRenderable)] {
        let question = Question(id: "target", title: "Select a target", kind: .singleSelection,
                                options: [QuestionOption(id: "agent", label: "TUIAgentUI")])
        return [
            ("prompt", prompt()),
            ("autocomplete", autocomplete()),
            ("attachment", AttachmentChip(id: 1, kind: .file, name: "Package.swift")),
            ("toast", ToastPresentation(kind: .failure, message: "Build failed")),
            ("user-message", UserMessageCard(text: "Inspect the semantic renderer.", attachments: ["Package.swift"],
                                              timestamp: "10:42")),
            ("reasoning", ReasoningDisclosure(phase: .completed, summary: "Renderer", body: "Checked cell widths",
                                               duration: .milliseconds(350), isExpanded: true)),
            ("tool-call", ToolCallRow(id: 1, label: "Run focused tests", state: .completed)),
            ("tool-result", ToolResultPanel(title: "Read", content: "48 lines", presentation: .panel)),
            ("shell-result", ShellResult(command: "swift test", workingDirectory: "~/TUIkit", output: "one\ntwo")),
            ("diff", AgentDiffContentView(unifiedDiff: """
            --- a/Renderer.swift
            +++ b/Renderer.swift
            @@ -1 +1 @@
            -invalidateAll()
            +invalidate(row)
            """)),
            ("diagnostics", DiagnosticsList(diagnostics: [
                DiagnosticPresentation(id: 1, severity: .warning, path: "App.swift", line: 7,
                                       column: 12, message: "Unused value"),
            ])),
            ("conversation", ConversationViewport(
                items: ["Old", "Visible response", "Newest"],
                state: ConversationViewportState(itemCount: 3, viewportExtent: 2, itemExtent: 1)
            )),
            ("assistant-message", AssistantMessage(
                markdown: ["Build failed."], reasoning: ["Checked diagnostics"],
                toolActivity: ["Read Package.swift"], diagnostics: ["One warning"],
                footer: AssistantMessageFooter(agentMode: "build", model: "swift-6", duration: .milliseconds(350))
            )),
            ("permission", permission()),
            ("question", QuestionPrompt(questions: [question])),
            ("todo", TodoItem(id: 1, title: "Compile target", detail: "Warnings are errors", state: .pending)),
            ("sidebar", SessionSidebar(sections: [
                SessionSidebarSection(kind: .files, title: "Files", items: ["Package.swift", "Rendering.swift"]),
            ], isOverlayPresented: true)),
            ("status", AgentStatusFooter(fields: [
                AgentStatusField(kind: .model, text: "swift-6", priority: 3),
                AgentStatusField(kind: .agent, text: "Build", priority: 4),
                AgentStatusField(kind: .contextUsage, text: "42% context", priority: 1),
            ])),
            ("pulse", BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(
                color: RGBA(redByte: 80, greenByte: 166, blueByte: 255)
            ))),
        ]
    }

    @MainActor
    private static func interactiveStates(
        width: Int,
        scheme: ColorScheme
    ) throws -> [(String, AgentRenderOutput)] {
        func context(reduceMotion: Bool = false) throws -> AgentRenderContext {
            try AgentRenderContext(width: width, scheme: scheme, elapsed: .milliseconds(600),
                                   reduceMotion: reduceMotion)
        }
        return [
            ("idle", prompt().render(in: try context())),
            ("focused", AttachmentChip(id: 1, kind: .file, name: "Package.swift", isFocused: true)
                .render(in: try context())),
            ("hovered", UserMessageCard<String>(text: "Inspect the renderer.", isHovered: true)
                .render(in: try context())),
            ("selected", autocomplete().render(in: try context())),
            ("disabled-prompt", prompt(isEnabled: false).render(in: try context())),
            ("disabled-menu", PromptAutocomplete(state: autocomplete().state, isEnabled: false)
                .render(in: try context())),
            ("busy-prompt", prompt(isBusy: true).render(in: try context())),
            ("busy-shell", ShellResult(command: "swift test", isRunning: true).render(in: try context())),
            ("error", ToolCallRow(id: 1, label: "Compile", state: .failed, errorBody: "Exit 1",
                                  isErrorExpanded: true).render(in: try context())),
            ("reduced-motion-reasoning", ReasoningDisclosure(phase: .running, summary: "Renderer", body: "Cells")
                .render(in: try context(reduceMotion: true))),
            ("reduced-motion-pulse", BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(
                color: RGBA(redByte: 80, greenByte: 166, blueByte: 255)
            )).render(in: try context(reduceMotion: true))),
            ("focused-dialog", permission().render(in: try context())),
        ]
    }

    private static func prompt(isEnabled: Bool = true, isBusy: Bool = false) -> AgentPrompt<String> {
        AgentPrompt(
            document: PromptDocument(text: "Fix the semantic renderer without changing package configuration."),
            configuration: AgentPromptConfiguration(
                isEnabled: isEnabled,
                isBusy: isBusy,
                metadata: AgentPromptMetadata(agent: "Build", model: "swift-6")
            ),
            actions: AgentPromptActions(submit: { _ in }, cancel: {}, paste: { _ in }, attach: { _ in })
        )
    }

    @MainActor
    private static func autocomplete() -> PromptAutocomplete<Int> {
        PromptAutocomplete(state: PromptAutocompleteState(suggestions: [
            PromptSuggestion(id: 1, kind: .command, title: "/test", detail: "Run focused tests",
                             insertion: PromptInsertion(replacementRange: 0..<0, text: "/test ")),
            PromptSuggestion(id: 2, kind: .file, title: "Rendering.swift",
                             insertion: PromptInsertion(replacementRange: 0..<0, text: "@Rendering.swift")),
        ], selectedIndex: 1))
    }

    private static func permission() -> PermissionPrompt {
        PermissionPrompt(
            requestedAction: "Delete generated files",
            resources: [".build"],
            risk: .destructive,
            choices: [
                PermissionChoice(scope: .deny, label: "Deny", risk: .low),
                PermissionChoice(scope: .once, label: "Allow once", risk: .destructive),
            ],
            focusedChoiceIndex: 1
        )
    }
}
