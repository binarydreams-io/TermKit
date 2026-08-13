import Foundation
import SwiftTUI

@main
@MainActor
struct ShowcaseApp {
    static func main() async throws {
        let environment = TerminalEnvironment.current()
        let capabilities = TerminalCapabilityDetector.capabilities(
            from: environment,
            terminfoHintProvider: nil,
            terminfoHintPolicy: TerminfoHintPolicy(),
            allowsOSC52: false
        )
        let transport = TerminalTransport()
        let session = TerminalSession(transport: transport, capabilities: capabilities)
        let size = try TerminalSizeReader(fileDescriptor: transport.outputFileDescriptor).read()
        let eventSource = try TerminalEventSource(inputFileDescriptor: transport.inputFileDescriptor)
        let view = try AgentShowcaseView(theme: SemanticTheme.standard.resolve(scheme: .dark))
        let runtime = TUIRuntime(
            view: view,
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: size.columns, height: size.rows),
            eventSource: eventSource,
            onInput: { event in
                if case .key(let key) = event, key.key == .escape || key.key == .text("q") {
                    try runtimeStopRequest()
                }
            }
        )
        RuntimeStopRequest.install { try runtime.stop() }
        defer { RuntimeStopRequest.clear() }
        try await runtime.run()
    }
}

@MainActor
private final class RuntimeStopRequest {
    private static var action: (() throws -> Void)?

    static func install(_ action: @escaping () throws -> Void) {
        self.action = action
    }

    static func clear() {
        action = nil
    }

    static func perform() throws {
        try action?()
    }
}

@MainActor
private func runtimeStopRequest() throws {
    try RuntimeStopRequest.perform()
}

@MainActor
private struct AgentShowcaseView: View {
    @State private var isAnimated = false

    let theme: ResolvedSemanticTheme
    let commandPalette: CommandPalette<String>

    private let headingStyle = CellStyle(attributes: .bold)
    private let componentHeight = 1

    init(theme: ResolvedSemanticTheme) {
        self.theme = theme
        commandPalette = CommandPalette(id: "showcase-command-palette", commands: [
            PaletteCommand(id: "focused", title: "Run focused tests") {
                writeShowcaseDiagnostic("SWIFTTUI_SHOWCASE_COMMAND=focused-tests\n")
            },
            PaletteCommand(id: "full", title: "Run full suite") {
                writeShowcaseDiagnostic("SWIFTTUI_SHOWCASE_COMMAND=full-suite\n")
            },
        ])
    }

    var graphBody: [NodeDescriptor] {
        VStack(alignment: .leading) {
            Text("SwiftTUI · Agent UI Showcase", id: "showcase-title", style: headingStyle)
            Text("retained graph · declarative state · tab then enter animates · q/esc quit", id: "showcase-subtitle")
            Button("Animate showcase", id: "animate-showcase") {
                isAnimated.toggle()
            }
            Text(
                isAnimated ? "Animation state: active" : "Animation state: idle",
                id: "animation-state",
                style: headingStyle
            )
            .offset(x: isAnimated ? 4 : 0)
            .opacity(isAnimated ? 0.65 : 1)
            .animation(.easeInOut(duration: .milliseconds(300)), value: isAnimated)

            heading(.prompt)
            AgentComponentView(prompt, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.commandPalette)
            commandPalette.selectList.view()
                .frame(width: 116, height: 2, alignment: .topLeading)

            heading(.messages)
            AgentComponentView(message, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.reasoning)
            AgentComponentView(reasoning, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.tools)
            AgentComponentView(tool, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.diff)
            AgentComponentView(diff, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.permissions)
            AgentComponentView(permission, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.questions)
            AgentComponentView(questions, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.toast)
            AgentComponentView(toast, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)

            heading(.sidebar)
            AgentComponentView(sidebar, theme: theme).frame(width: 116, height: componentHeight, alignment: .topLeading)
        }
        .frame(width: 120, height: 40, alignment: .topLeading)
        .graphBody
    }

    private func heading(_ component: ShowcaseComponent) -> Text {
        let entry = ShowcaseCatalog.requiredEntries.first { $0.component == component }
        return Text(entry?.title ?? component.rawValue, id: SemanticID(rawValue: "showcase-\(component.rawValue)-heading"), style: headingStyle)
    }

    private var prompt: AgentPrompt<String> {
        AgentPrompt(
            document: PromptDocument(text: "Explain the failing renderer test"),
            configuration: AgentPromptConfiguration(
                metadata: AgentPromptMetadata(agent: "Build", model: "Swift", provider: "Local")
            ),
            actions: AgentPromptActions(submit: { _ in }, cancel: {}, paste: { _ in }, attach: { _ in })
        )
    }

    private var message: UserMessageCard<String> {
        UserMessageCard(
            text: "The terminal redraws too much.",
            attachments: ["RendererPropertyTests.swift"],
            timestamp: "now"
        )
    }

    private var reasoning: ReasoningDisclosure<String> {
        ReasoningDisclosure(
            phase: .running,
            summary: "Checking damage propagation",
            body: "The changed row does not invalidate its siblings."
        )
    }

    private var tool: ToolCallRow<String> {
        ToolCallRow(id: "test", label: "Run focused tests", state: .running)
    }

    private var diff: AgentDiffContentView {
        AgentDiffContentView(unifiedDiff: """
        --- a/Renderer.swift
        +++ b/Renderer.swift
        @@ -1 +1 @@
        -invalidateAll()
        +invalidate(row)
        """)
    }

    private var permission: PermissionPrompt {
        PermissionPrompt(
            requestedAction: "Run package tests",
            resources: ["Swift package build directory"],
            risk: .low,
            choices: [
                PermissionChoice(scope: .once, label: "Allow once", risk: .low),
                PermissionChoice(scope: .deny, label: "Deny", risk: .low),
            ]
        )
    }

    private var questions: QuestionPrompt {
        var prompt = QuestionPrompt(questions: [
            Question(
                id: "scope",
                title: "Which suite should run?",
                kind: .singleSelection,
                options: [QuestionOption(id: "focused", label: "Focused"), QuestionOption(id: "full", label: "Full")],
                validationRules: [.required]
            ),
        ])
        prompt.setAnswer(.optionIDs(["focused"]), forQuestionID: "scope")
        return prompt
    }

    private var toast: ToastPresentation {
        ToastPresentation(kind: .success, message: "85 runtime tests passed")
    }

    private var sidebar: SessionSidebar<String> {
        SessionSidebar(
            sections: [
                SessionSidebarSection(kind: .metadata, title: "Session", items: ["SwiftTUI 0.1 preview"]),
                SessionSidebarSection(kind: .todos, title: "Todos", items: ["Renderer complete", "Docs in progress"]),
            ],
            isOverlayPresented: true
        )
    }
}

private func writeShowcaseDiagnostic(_ value: String) {
    FileHandle.standardError.write(Data(value.utf8))
}
