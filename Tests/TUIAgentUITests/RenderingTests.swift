import Testing
import TUIControls
import TUIDesign
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIRichText
import TUIViewGraph

@testable import TUIAgentUI

struct AgentRenderingTests {
    @Test("Agent component leaf paints production output and offsets semantics")
    @MainActor
    func componentLeaf() throws {
        let view = try AgentComponentView(
            ToastPresentation(kind: .information, message: "界 ready"),
            scheme: .dark
        )
        let descriptor = try #require(view.graphBody.first)
        var surface = TUIRenderer.Surface(size: CellSize(width: 14, height: 3))
        var resources = ControlRenderResources()

        let semantics = try view.paint(
            into: &surface,
            context: PaintContext(
                origin: CellPoint(x: 2, y: 1),
                clip: CellRect(x: 2, y: 1, width: 10, height: 1)
            ),
            resources: &resources
        )

        #expect(descriptor.primitive(as: AgentComponentView<ToastPresentation>.self) != nil)
        #expect(view.sizeThatFits(ProposedCellSize(width: 10)) == CellSize(width: 10, height: 1))
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 4, y: 1)].graphemeID) == "界")
        #expect(surface[CellPoint(x: 4, y: 1)].displayWidth == 2)
        #expect(semantics.frame == CellRect(x: 2, y: 1, width: 10, height: 1))
        #expect(semantics.role == .status)
        try surface.validateWideCells()
    }

    @Test("Bound prompt leaf measures and paints production output")
    @MainActor
    func boundPromptLeaf() throws {
        let model = RenderingPromptModel()
        let prompt = AgentPrompt<String>(
            model.binding,
            actions: AgentPromptActions(submit: { _ in }, cancel: {}, paste: { _ in }, attach: { _ in })
        )
        let leaf = try #require(prompt.graphBody.first?.children.first?.children.first)
        let renderable = try #require(leaf.primitive(as: (any SemanticRenderable).self))
        let size = renderable.sizeThatFits(ProposedCellSize(width: 40, height: 10))
        var surface = TUIRenderer.Surface(size: CellSize(width: 40, height: 10))
        var resources = ControlRenderResources()

        let semantics = try renderable.paint(
            into: &surface,
            context: PaintContext(origin: .zero, clip: CellRect(x: 0, y: 0, width: 40, height: 10)),
            resources: &resources
        )

        #expect(size.width > 0)
        #expect(size.height > 0)
        #expect(semantics.role == .group)
        #expect(semantics.children.first?.role == .textEditor)
        #expect(semantics.frame?.isEmpty == false)
        #expect(leaf.focus.isFocusable)
        #expect((0..<size.height).contains { y in
            (0..<size.width).contains { x in
                resources.graphemes.value(for: surface[CellPoint(x: x, y: y)].graphemeID) == "R"
            }
        })
    }

    @Test("Toast renders a semantic accent rail and status")
    func toast() throws {
        let output = ToastPresentation(kind: .failure, message: "Build failed").render(
            in: try AgentRenderContext(width: 40, scheme: .dark)
        )

        #expect(output.plainText.contains("▌ Build failed"))
        #expect(output.semantics.role == .status)
    }

    @Test("Prompt uses element background and separates status semantics")
    func promptPresentationSemantics() throws {
        let output = AgentPrompt<String>(
            document: PromptDocument(text: "Build"),
            configuration: AgentPromptConfiguration(isBusy: true),
            actions: Self.noPromptActions()
        ).render(in: try AgentRenderContext(width: 40, scheme: .dark))

        #expect(output.cells.rows.flatMap { $0 }.compactMap { $0 }.allSatisfy { $0.backgroundRole == .element })
        #expect(output.semantics.role == .group)
        #expect(output.semantics.children.first?.role == .textEditor)
        #expect(output.semantics.children.last?.role == .status)
    }

    @Test("Prompt metadata is a separate semantic paint leaf")
    @MainActor
    func promptMetadataLeaf() throws {
        let model = RenderingPromptModel()
        let prompt = AgentPrompt<String>(
            model.binding,
            configuration: AgentPromptConfiguration(metadata: AgentPromptMetadata(model: "swift-6")),
            actions: Self.noPromptActions()
        )
        let graph = ViewGraph()
        try graph.commit(graph.prepare(prompt))
        let content = try #require(graph.root?.children.first?.children.first)

        #expect(content.children.count == 2)
        #expect(content.children[0].primitive(as: AgentPromptRenderLeaf<String>.self) != nil)
        #expect(content.children[1].children.first?.primitive(as: AgentPromptMetadataLeaf.self) != nil)
        let editor = try #require(content.children[0].primitive(as: AgentPromptRenderLeaf<String>.self))
        #expect(editor.prompt.render(in: try AgentRenderContext(width: 40, scheme: .dark)).plainText.contains("swift-6") == false)
    }

    @Test("User message applies its configured semantic rail color")
    func userMessageRailColor() throws {
        let output = UserMessageCard<String>(text: "Hello", agentColor: .success).render(
            in: try AgentRenderContext(width: 40, scheme: .dark)
        )

        #expect(output.cells.rows.flatMap { $0 }.compactMap { $0 }.first { $0.grapheme == "▌" }?.foregroundRole == .success)
    }

    @Test("Completed reasoning renders its optional summary")
    func completedReasoningSummary() throws {
        let output = ReasoningDisclosure(
            phase: .completed,
            summary: "Checked renderer",
            body: "Details"
        ).render(in: try AgentRenderContext(width: 40, scheme: .dark))

        #expect(output.plainText.contains("Thought · Checked renderer"))
    }

    static let widths = [40, 80, 120, 180]
    static let schemes: [ColorScheme] = [.light, .dark]

    @Test("Core components produce semantic cell grids", arguments: widths, schemes)
    @MainActor
    func componentMatrix(width: Int, scheme: ColorScheme) throws {
        let context = try AgentRenderContext(width: width, scheme: scheme, elapsed: .milliseconds(240))
        let components: [any AgentComponentRenderable] = [
            AgentPrompt<String>(
                document: PromptDocument(text: "Explain the failing build and propose a focused fix."),
                configuration: AgentPromptConfiguration(
                    metadata: AgentPromptMetadata(agent: "Build", model: "swift-6", provider: "local", variant: "fast")
                ),
                actions: Self.noPromptActions()
            ),
            PromptAutocomplete(state: PromptAutocompleteState(suggestions: [
                PromptSuggestion(id: 1, kind: .command, title: "/test", detail: "Run focused tests",
                                 insertion: PromptInsertion(replacementRange: 0..<0, text: "/test ")),
                PromptSuggestion(id: 2, kind: .file, title: "Sources/App.swift",
                                 insertion: PromptInsertion(replacementRange: 0..<0, text: "@Sources/App.swift")),
            ], selectedIndex: 1)),
            AttachmentChip(id: 1, kind: .file, name: "Package.swift", isFocused: true),
            UserMessageCard(text: "Please inspect the renderer.", attachments: ["Package.swift"],
                            timestamp: "10:42", isQueued: true),
            ReasoningDisclosure(phase: .running, summary: "Inspecting renderer APIs", body: "Checking cell widths"),
            ToolCallRow(id: 1, label: "Run swift test", state: .failed,
                        errorBody: "Compiler exited with status 1", isErrorExpanded: true),
            ToolResultPanel(title: "Read", content: "48 lines", presentation: .panel),
            ShellResult(command: "swift test", workingDirectory: "~/TUIkit", output: "one\ntwo\nthree",
                        isRunning: true),
            DiagnosticsList(diagnostics: [
                DiagnosticPresentation(id: 1, severity: .warning, path: "App.swift", line: 7,
                                       column: 12, message: "Unused value"),
            ]),
            PermissionPrompt(requestedAction: "Delete generated files", resources: [".build"], risk: .destructive,
                             choices: [PermissionChoice(scope: .deny, label: "Deny", risk: .low),
                                       PermissionChoice(scope: .once, label: "Allow once", risk: .destructive)],
                             focusedChoiceIndex: 1),
            TodoItem(id: 1, title: "Compile target", detail: "Warnings are errors", state: .inProgress),
            AgentStatusFooter(fields: [
                AgentStatusField(kind: .model, text: "swift-6", priority: 3),
                AgentStatusField(kind: .agent, text: "Build", priority: 4),
                AgentStatusField(kind: .contextUsage, text: "42% context", priority: 1),
                AgentStatusField(kind: .connection, text: "connected", priority: 2),
            ]),
        ]

        for component in components {
            let output = component.render(in: context)
            #expect(output.cells.width > 0)
            #expect(output.cells.width <= width)
            #expect(output.cells.rows.allSatisfy { $0.count == output.cells.width })
            #expect(output.semantics.frame?.height == output.cells.height)
            #expect(output.plainText.isEmpty == false)
            #expect(output.theme.scheme == scheme)
        }
    }

    @Test("Conversation, assistant, questions, and sidebar perform executable layout", arguments: widths, schemes)
    func compositeMatrix(width: Int, scheme: ColorScheme) throws {
        let context = try AgentRenderContext(width: width, scheme: scheme)
        let viewportState = ConversationViewportState(itemCount: 3, viewportExtent: 2, itemExtent: 1)
        let question = Question(id: "target", title: "Select a target", kind: .singleSelection,
                                options: [QuestionOption(id: "agent", label: "TUIAgentUI")],
                                validationRules: [.required])
        var questions = QuestionPrompt(questions: [question])
        questions.setAnswer(.optionIDs(["agent"]), forQuestionID: "target")
        let components: [any AgentComponentRenderable] = [
            ConversationViewport(items: ["Old", "Visible response", "Newest"], state: viewportState),
            AssistantMessage(markdown: ["Build failed."], reasoning: ["Checked diagnostics"],
                             toolActivity: ["Read Package.swift"], diagnostics: ["One warning"],
                             footer: AssistantMessageFooter(agentMode: "build", model: "swift-6",
                                                            duration: .milliseconds(350))),
            questions,
            SessionSidebar(sections: [SessionSidebarSection(kind: .files, title: "Files",
                                                             items: ["Package.swift", "Rendering.swift"])],
                           isOverlayPresented: true),
        ]

        for component in components {
            let output = component.render(in: context)
            #expect(output.cells.width <= width)
            #expect(output.cells.height > 0)
            #expect(output.semantics.children.isEmpty == false)
        }
    }

    @Test("Focused, disabled, busy, error, and reduced-motion states are semantic")
    @MainActor
    func representativeStates() throws {
        let context = try AgentRenderContext(width: 80, scheme: .dark, reduceMotion: true)
        let disabled = AgentPrompt<String>(
            document: PromptDocument(),
            configuration: AgentPromptConfiguration(isEnabled: false),
            actions: Self.noPromptActions()
        ).render(in: context)
        let busy = ShellResult(command: "build", isRunning: true).render(in: context)
        let error = DiagnosticsList(diagnostics: [
            DiagnosticPresentation(id: 1, severity: .error, message: "Build failed"),
        ]).render(in: context)
        let selected = PromptAutocomplete(state: PromptAutocompleteState(suggestions: [
            PromptSuggestion(id: 1, kind: .symbol, title: "Renderer",
                             insertion: PromptInsertion(replacementRange: 0..<0, text: "Renderer")),
        ])).render(in: context)

        #expect(disabled.semantics.state.contains(.disabled))
        #expect(disabled.semantics.actions.isEmpty)
        #expect(busy.semantics.state.contains(.busy))
        #expect(busy.plainText.contains("Running..."))
        #expect(error.plainText.contains("Build failed"))
        #expect(selected.semantics.children.first?.state.contains(.selected) == true)
    }

    @Test("Background pulse becomes static under reduced motion", arguments: widths, schemes)
    func pulseMatrix(width: Int, scheme: ColorScheme) throws {
        let pulse = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(
            color: RGBA(redByte: 80, greenByte: 166, blueByte: 255)
        ))
        let animated = pulse.render(in: try AgentRenderContext(width: width, scheme: scheme,
                                                               elapsed: .milliseconds(600)))
        let reduced = pulse.render(in: try AgentRenderContext(width: width, scheme: scheme,
                                                              elapsed: .milliseconds(600), reduceMotion: true))
        let staticContext = try AgentRenderContext(width: width, scheme: scheme, reduceMotion: true)
        let staticOutput = pulse.render(in: staticContext)

        #expect(animated.semantics.state.contains(.busy))
        #expect(reduced.semantics.state.contains(.busy) == false)
        #expect(reduced.plainText == staticOutput.plainText)
    }

    @Test("Prompt cell-grid snapshot adapts at canonical widths and themes", arguments: widths, schemes)
    func promptSnapshot(width: Int, scheme: ColorScheme) throws {
        let prompt = AgentPrompt<String>(
            document: PromptDocument(text: "Fix the semantic renderer without changing package configuration."),
            configuration: AgentPromptConfiguration(
                metadata: AgentPromptMetadata(agent: "Build", model: "swift-6")
            ),
            actions: Self.noPromptActions()
        )

        let output = prompt.render(in: try AgentRenderContext(width: width, scheme: scheme))
        let snapshot = output.plainText
        let expected: [Int: String] = [
            40: "\n▌  Fix the semantic renderer without\n▌  changing package configuration.\n" + String(repeating: "▄", count: 40),
            80: "\n▌  Fix the semantic renderer without changing package configuration.\n" + String(repeating: "▄", count: 75),
            120: "\n▌  Fix the semantic renderer without changing package configuration.\n" + String(repeating: "▄", count: 84),
            180: "\n▌  Fix the semantic renderer without changing package configuration.\n" + String(repeating: "▄", count: 125),
        ]

        #expect(snapshot == expected[width])
        #expect(output.theme.scheme == scheme)
        #expect(output.cells.rows.flatMap { $0 }.compactMap { $0 }.contains { $0.role == .listMarker })
    }

    private static func noPromptActions() -> AgentPromptActions<String> {
        AgentPromptActions(submit: { _ in }, cancel: {}, paste: { _ in }, attach: { _ in })
    }
}

@MainActor
private final class RenderingPromptModel {
    var document = PromptDocument(text: "Runtime prompt")

    var binding: Binding<PromptDocument> {
        Binding(get: { self.document }, set: { self.document = $0 })
    }
}
