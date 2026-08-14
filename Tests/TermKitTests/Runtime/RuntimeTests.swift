import Foundation
import Testing

@testable import TermKit

@MainActor
struct RuntimeTests {
    @Test("Resize updates terminal-size environment dependencies")
    func terminalSizeEnvironmentPropagation() throws {
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: TerminalSizeProbe(),
            presenter: presenter,
            terminalSize: CellSize(width: 40, height: 10),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        #expect(surfaceText(presenter).contains("40x10"))

        try runtime.process(.resize(CellSize(width: 72, height: 24)))
        _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

        #expect(surfaceText(presenter).contains("72x24"))
        #expect(runtime.nextDeadline(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)) == nil)
    }

    @Test("Application commands precede focused control dispatch")
    func applicationCommandDispatch() throws {
        let recorder = RuntimeCommandRecorder()
        let commands = KeyboardCommandSet([
            KeyboardCommand(
                id: "play-pause",
                title: "Play or pause",
                shortcut: KeyboardShortcut(.character(" "))
            ) {
                recorder.invocations += 1
            }
        ])
        let runtime = Runtime(
            view: Text("Player"),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 1),
            timeSource: DeterministicTimeSource(),
            commands: commands
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        try runtime.process(.input(.key(TerminalKeyEvent(key: .text(" ")))))

        #expect(recorder.invocations == 1)
    }

    @Test("Progress semantics adjust without motion or idle frame demand")
    func progressSemanticRuntimeIntegration() throws {
        let model = RuntimeProgressModel(value: 0.4)
        let runtime = Runtime(
            view: ProgressBar(value: model.binding, id: "volume", label: "Volume", adjustmentStep: 0.1)
                .frame(width: 10),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 10, height: 1),
            motionPolicy: .reduced,
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        let first = try #require(try runtime.renderIfDue(at: .zero))

        #expect(first.semantics.node(withID: "volume")?.value == "40%")
        #expect(first.semantics.node(withID: "volume")?.actions == [.increment, .decrement])
        #expect(first.stats.activeAnimationCount == 0)
        #expect(runtime.nextDeadline(at: .zero) == nil)
        #expect(runtime.performSemanticAction(.increment, on: "volume"))

        let secondInstant = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
        let second = try #require(try runtime.renderIfDue(at: secondInstant))
        #expect(second.semantics.node(withID: "volume")?.value == "50%")
        #expect(runtime.nextDeadline(at: secondInstant) == nil)
    }

    @Test("Bound agent prompt renders and handles focused runtime input")
    func boundAgentPromptRuntimeIntegration() throws {
        let model = RuntimePromptModel()
        let recorder = RuntimePromptRecorder()
        var externalInputs: [TerminalInputEvent] = []
        let prompt = AgentPrompt<String>(
            model.binding,
            actions: AgentPromptActions(
                submit: { recorder.submitted.append($0) },
                cancel: { recorder.cancelCount += 1 },
                paste: { recorder.pasted.append($0) },
                attach: { _ in }
            )
        )
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: prompt,
            presenter: presenter,
            terminalSize: CellSize(width: 40, height: 10),
            timeSource: DeterministicTimeSource(),
            onInput: { externalInputs.append($0) }
        )
        try runtime.start()

        let first = try #require(try runtime.renderIfDue(at: .zero))
        let promptNode = try #require(runtime.graph.focusableNodes().first)
        let promptFrame = try #require(promptNode.cachedFrame)
        let promptSemantics = try #require(first.semantics.node(withID: "agent-prompt"))
        let editorSemantics = try #require(first.semantics.node(withID: "agent-prompt-editor"))

        #expect(promptFrame.isEmpty == false)
        #expect(promptSemantics.frame?.isEmpty == false)
        #expect(promptSemantics.role == .group)
        #expect(editorSemantics.role == .textEditor)
        #expect(editorSemantics.actions == [.focus, .submit])
        #expect(surfaceText(presenter).contains("Runtime"))

        let inputs: [TerminalInputEvent] = [
            .key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .text("!"))),
            .paste(" pasted"),
            .key(TerminalKeyEvent(key: .enter)),
            .key(TerminalKeyEvent(key: .enter, modifiers: .shift)),
            .key(TerminalKeyEvent(key: .escape)),
        ]
        for input in inputs {
            try runtime.process(.input(input))
        }
        let second = try #require(
            try runtime.renderIfDue(
                at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)
            )
        )

        #expect(model.document.text == "Runtime! pasted\n")
        #expect(recorder.pasted == [" pasted"])
        #expect(recorder.submitted.map(\.text) == ["Runtime! pasted"])
        #expect(recorder.cancelCount == 1)
        #expect(externalInputs == inputs)
        #expect(runtime.graph.focusableNodes().first?.id == promptNode.id)
        #expect(second.semantics.node(withID: "agent-prompt")?.state.contains(.focused) == true)
        #expect(second.semantics.node(withID: "agent-prompt")?.frame?.isEmpty == false)
    }

    @Test("Agent prompt metadata insertion transitions only metadata paint for 150 milliseconds")
    func agentPromptMetadataInsertionTransition() throws {
        let model = RuntimePromptTransitionModel()
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: RuntimePromptTransitionRoot(model: model),
            presenter: presenter,
            terminalSize: CellSize(width: 40, height: 6),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        let initial = try #require(try runtime.renderIfDue(at: .zero))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
        let editorNode = try #require(runtime.graph.focusableNodes().first)
        let editorID = editorNode.id
        let initialEditorFrame = try #require(initial.semantics.node(withID: "agent-prompt-editor")?.frame)

        model.configuration.metadata = AgentPromptMetadata(model: "swift-6")
        runtime.invalidate()
        let insertionStart = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
        let start = try #require(try runtime.renderIfDue(at: insertionStart))
        let metadataNode = try #require(
            firstNode(runtime.graph.root) {
                $0.animationStatus(for: .transitionVisibility) != nil
            }
        )
        let metadataFrame = try #require(start.semantics.node(withID: "agent-prompt-metadata")?.frame)
        let editorPoint = try #require(cellPoint(for: "R", in: presenter))
        let editorForeground = try #require(foregroundRGBA(at: editorPoint, presenter: presenter))

        #expect(metadataNode.animationStatus(for: .transitionVisibility) == .running)
        #expect(metadataNode.presentationValue(PresentationProperties.transitionVisibility, at: insertionStart) == 0)
        #expect(runtime.nextDeadline(at: insertionStart) == insertionStart.advanced(by: FrameScheduler.minimumFrameInterval))
        #expect(runtime.graph.focusableNodes().first?.id == editorID)
        #expect(editorNode.animationStatus(for: .transitionVisibility) == nil)
        #expect(start.semantics.node(withID: "agent-prompt")?.state.contains(.focused) == true)
        #expect(start.semantics.node(withID: "agent-prompt-editor")?.frame == initialEditorFrame)
        #expect(cellPoint(for: "s", in: presenter) == nil)
        #expect(foregroundRGBA(at: editorPoint, presenter: presenter) == editorForeground)

        let midpoint = insertionStart.advanced(by: .milliseconds(75))
        let middle = try #require(try runtime.renderIfDue(at: midpoint))
        let sampledMidpoint = try #require(
            metadataNode.presentationValue(
                PresentationProperties.transitionVisibility,
                at: midpoint
            )
        )
        let metadataPoint = try #require(cellPoint(for: "s", in: presenter))
        let metadataForeground = try #require(foregroundRGBA(at: metadataPoint, presenter: presenter))
        let middleEditorPoint = try #require(cellPoint(for: "R", in: presenter))

        #expect(metadataNode.animationStatus(for: .transitionVisibility) == .running)
        #expect(sampledMidpoint > 0 && sampledMidpoint < 1)
        #expect(metadataForeground.red < editorForeground.red)
        #expect(metadataForeground.green < editorForeground.green)
        #expect(metadataForeground.blue < editorForeground.blue)
        #expect(foregroundRGBA(at: middleEditorPoint, presenter: presenter) == editorForeground)
        #expect(middle.semantics.node(withID: "agent-prompt-editor")?.frame == initialEditorFrame)
        #expect(runtime.graph.focusableNodes().first?.id == editorID)

        let insertionEnd = insertionStart.advanced(by: .milliseconds(150))
        let end = try #require(try runtime.renderIfDue(at: insertionEnd))
        let finalMetadataPoint = try #require(cellPoint(for: "s", in: presenter))

        #expect(metadataNode.animationStatus(for: .transitionVisibility) == .completed)
        #expect(metadataNode.presentationValue(PresentationProperties.transitionVisibility, at: insertionEnd) == 1)
        #expect(foregroundRGBA(at: finalMetadataPoint, presenter: presenter) == nil)
        #expect(end.semantics.node(withID: "agent-prompt-metadata")?.frame == metadataFrame)
        #expect(end.semantics.node(withID: "agent-prompt-editor")?.frame == initialEditorFrame)
        #expect(runtime.graph.focusableNodes().first?.id == editorID)
        #expect(runtime.nextDeadline(at: insertionEnd) == nil)

        let staticModel = RuntimePromptTransitionModel(animationsEnabled: false)
        let staticPresenter = FramePresenter(session: FakeTerminalSession())
        let staticRuntime = Runtime(
            view: RuntimePromptTransitionRoot(model: staticModel),
            presenter: staticPresenter,
            terminalSize: CellSize(width: 40, height: 6),
            timeSource: DeterministicTimeSource()
        )
        try staticRuntime.start()
        _ = try staticRuntime.renderIfDue(at: .zero)
        staticModel.configuration.metadata = AgentPromptMetadata(model: "swift-6")
        staticRuntime.invalidate()
        let staticInsertion = TimeInstant.zero.advanced(by: .milliseconds(20))
        let staticFrame = try #require(try staticRuntime.renderIfDue(at: staticInsertion))

        #expect(staticFrame.semantics.node(withID: "agent-prompt-metadata") != nil)
        #expect(cellPoint(for: "s", in: staticPresenter) != nil)
        #expect(
            firstNode(staticRuntime.graph.root) {
                $0.animationStatus(for: .transitionVisibility) != nil
            } == nil
        )
        #expect(staticFrame.stats.activeAnimationCount == 0)
        #expect(staticRuntime.nextDeadline(at: staticInsertion) == nil)
    }

    @Test("Prompt runtime handles character selection, deletion, multiline replacement, and rejected paste")
    func promptEditingRuntimeIntegration() throws {
        let model = RuntimePromptModel(document: PromptDocument(text: "A🦊\nBC"))
        let recorder = RuntimePromptRecorder()
        let prompt = AgentPrompt<String>(
            model.binding,
            configuration: AgentPromptConfiguration(
                pastePolicy: AgentPromptPastePolicy(largePasteThreshold: 4, largePasteBehavior: .reject)
            ),
            actions: AgentPromptActions(
                submit: { _ in },
                cancel: {},
                paste: { recorder.pasted.append($0) },
                attach: { _ in },
                diagnostic: { recorder.diagnostics.append($0) }
            )
        )
        let runtime = Runtime(
            view: prompt,
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 40, height: 8),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        for input in [
            TerminalInputEvent.key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .left, modifiers: .shift)),
            .key(TerminalKeyEvent(key: .left, modifiers: .shift)),
            .key(TerminalKeyEvent(key: .left, modifiers: .shift)),
            .key(TerminalKeyEvent(key: .backspace)),
            .paste("12345"),
        ] {
            try runtime.process(.input(input))
        }

        #expect(model.document == PromptDocument(text: "A🦊", selection: PromptSelection(caret: 2)))
        #expect(recorder.pasted.isEmpty)
        #expect(recorder.diagnostics == [.pasteRejected(characterCount: 5, limit: 4)])
    }

    @Test("Running reasoning requests shared timeline cadence and static states stop")
    func reasoningTimelineRuntimeIntegration() throws {
        let running = Runtime(
            view: AgentComponentView(
                ReasoningDisclosure(phase: .running, body: "body"),
                theme: runtimeAgentTheme
            ),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 2),
            timeSource: DeterministicTimeSource()
        )
        try running.start()
        _ = try running.renderIfDue(at: .zero)
        #expect(running.nextDeadline(at: .zero) == .zero.advanced(by: .milliseconds(120)))

        let completed = Runtime(
            view: AgentComponentView(
                ReasoningDisclosure(phase: .completed, body: "body"),
                theme: runtimeAgentTheme
            ),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 2),
            timeSource: DeterministicTimeSource()
        )
        try completed.start()
        _ = try completed.renderIfDue(at: .zero)
        #expect(completed.nextDeadline(at: .zero) == nil)

        let reduced = Runtime(
            view: AgentComponentView(
                ReasoningDisclosure(phase: .running, body: "body"),
                theme: runtimeAgentTheme
            ),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 2),
            motionPolicy: .reduced,
            timeSource: DeterministicTimeSource()
        )
        try reduced.start()
        _ = try reduced.renderIfDue(at: .zero)
        #expect(reduced.nextDeadline(at: .zero) == nil)
    }

    @Test("Viewport semantic actions and autocomplete input execute through runtime")
    func agentAdaptersRuntimeIntegration() throws {
        let viewportModel = RuntimeViewportModel()
        let viewportRuntime = Runtime(
            view: AgentComponentView(
                items: ["one", "two", "three"],
                state: Binding(get: { viewportModel.state }, set: { viewportModel.state = $0 }),
                theme: runtimeAgentTheme,
                actions: ConversationViewportActions(scrollForward: { viewportModel.forwardCount += 1 })
            ),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 3),
            timeSource: DeterministicTimeSource()
        )
        try viewportRuntime.start()
        _ = try viewportRuntime.renderIfDue(at: .zero)

        #expect(viewportRuntime.performSemanticAction(.scrollForward, on: "conversation"))
        #expect(viewportModel.state.scrollState.offset == 1)
        #expect(viewportModel.forwardCount == 1)

        let autocompleteModel = RuntimeAutocompleteModel()
        let autocomplete = PromptAutocomplete(
            state: PromptAutocompleteState(
                suggestions: [
                    PromptSuggestion(id: 1, kind: .command, title: "One", insertion: PromptInsertion(replacementRange: 0..<0, text: "one")),
                    PromptSuggestion(id: 2, kind: .command, title: "Two", insertion: PromptInsertion(replacementRange: 0..<0, text: "two")),
                ],
                anchorColumn: 3,
                anchorRow: 2
            )
        ) { autocompleteModel.insertions.append($0) }
        let autocompleteRuntime = Runtime(
            view: autocomplete,
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 6),
            timeSource: DeterministicTimeSource()
        )
        try autocompleteRuntime.start()
        let first = try #require(try autocompleteRuntime.renderIfDue(at: .zero))
        #expect(first.semantics.node(withID: "prompt-autocomplete")?.frame?.origin == CellPoint(x: 3, y: 2))
        try autocompleteRuntime.process(.input(.key(TerminalKeyEvent(key: .tab))))
        try autocompleteRuntime.process(.input(.key(TerminalKeyEvent(key: .down))))
        try autocompleteRuntime.process(.input(.key(TerminalKeyEvent(key: .enter))))
        #expect(autocompleteModel.insertions.last?.text == "two")

        try autocompleteRuntime.process(
            .input(
                .mouse(
                    TerminalMouseEvent(
                        action: .release(.left),
                        position: TerminalCellPoint(column: 3, row: 3)
                    )
                )
            )
        )
        #expect(autocompleteModel.insertions.last?.text == "one")
    }

    @Test("Agent components execute keyboard, pointer, focus, and dismissal actions through runtime")
    func agentComponentRuntimeActions() throws {
        let model = RuntimeAgentComponentModel()
        let runtime = Runtime(
            view: RuntimeAgentComponentRoot(model: model),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 40, height: 24),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        #expect(runtime.semantics.node(withID: "reasoning")?.actions == [.activate])

        try runtime.process(
            .input(
                .mouse(
                    TerminalMouseEvent(
                        action: .release(.left),
                        position: TerminalCellPoint(column: 1, row: 0)
                    )
                )
            )
        )
        for input in [
            TerminalInputEvent.key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .enter)),
            .key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .enter)),
            .key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .enter)),
            .key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .down)),
            .key(TerminalKeyEvent(key: .enter)),
            .key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .escape)),
        ] {
            try runtime.process(.input(input))
        }

        #expect(model.focusedAttachments == [7])
        #expect(model.removedAttachments == [7])
        #expect(model.reasoningToggleCount == 1)
        #expect(model.toolFailureIDs == [9])
        #expect(model.shellToggleCount == 1)
        #expect(model.navigatedDiagnosticIDs == [2])
        #expect(model.sidebarDismissCount == 1)
    }

    @Test("Agent component semantics expose actions only when a runtime adapter can execute them")
    func agentComponentExecutableSemantics() throws {
        let plainRuntime = Runtime(
            view: AgentComponentView(
                ReasoningDisclosure(phase: .completed, body: "body"),
                theme: runtimeAgentTheme
            ),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 2),
            timeSource: DeterministicTimeSource()
        )
        try plainRuntime.start()
        let plainFrame = try #require(try plainRuntime.renderIfDue(at: .zero))

        #expect(plainFrame.semantics.node(withID: "reasoning")?.actions.isEmpty == true)
    }

    @Test("Permission prompt traps runtime input and executes the focused choice")
    func permissionPromptRuntimeActions() throws {
        let model = RuntimePermissionModel()
        let runtime = Runtime(
            view: RuntimePermissionRoot(model: model),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 40, height: 10),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        for input in [
            TerminalInputEvent.key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .down)),
            .key(TerminalKeyEvent(key: .escape)),
            .key(TerminalKeyEvent(key: .enter)),
        ] {
            try runtime.process(.input(input))
        }

        #expect(model.prompt.focusedChoice.scope == .once)
        #expect(model.choices.map(\.scope) == [.once])
    }

    @Test("Question prompt edits current steps and navigates through runtime input")
    func questionPromptRuntimeActions() throws {
        let model = RuntimeQuestionModel()
        let runtime = Runtime(
            view: RuntimeQuestionRoot(model: model),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 40, height: 12),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        for input in [
            TerminalInputEvent.key(TerminalKeyEvent(key: .tab)),
            .key(TerminalKeyEvent(key: .down)),
            .key(TerminalKeyEvent(key: .enter)),
            .key(TerminalKeyEvent(key: .right)),
            .key(TerminalKeyEvent(key: .text("hello"))),
            .key(TerminalKeyEvent(key: .left)),
            .key(TerminalKeyEvent(key: .right)),
            .key(TerminalKeyEvent(key: .backspace)),
            .paste("!"),
            .key(TerminalKeyEvent(key: .enter)),
        ] {
            try runtime.process(.input(input))
        }

        #expect(model.prompt.answers["mode"] == .optionIDs(["b"]))
        #expect(model.prompt.answers["note"] == .text("hell!"))
        #expect(model.state.stepIndex == 1)
        #expect(model.submissions.count == 1)
        #expect(model.cancelCount == 0)
    }

    @Test("Declarative runtime lays out, paints, focuses, activates, and preserves identity")
    func declarativeRuntimeIntegration() throws {
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session)
        let root = DeclarativeTestRoot()
        let runtime = Runtime(
            view: root,
            presenter: presenter,
            terminalSize: CellSize(width: 16, height: 8),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()

        let first = try #require(try runtime.renderIfDue(at: .zero))
        let buttonNode = try #require(runtime.graph.focusableNodes().first)
        let buttonID = buttonNode.id
        #expect(first.semantics.node(withID: "title")?.frame == CellRect(x: 1, y: 1, width: 2, height: 1))
        #expect(first.semantics.node(withID: "action")?.frame == CellRect(x: 1, y: 2, width: 3, height: 1))
        #expect(first.semantics.node(withID: "rich")?.frame == CellRect(x: 1, y: 3, width: 4, height: 1))
        #expect(first.semantics.node(withID: "toast")?.frame == CellRect(x: 1, y: 4, width: 14, height: 1))
        #expect(surfaceText(presenter).contains("界"))
        #expect(surfaceText(presenter).contains("Run"))
        #expect(surfaceText(presenter).contains("Rich"))
        #expect(surfaceText(presenter).contains("Agent"))

        try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .enter))))
        let second = try #require(try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)))

        #expect(second.semantics.node(withID: "title")?.label == "Done")
        #expect(second.semantics.node(withID: "action")?.state.contains(.focused) == true)
        #expect(runtime.graph.focusableNodes().first?.id == buttonID)

        try runtime.process(
            .input(
                .mouse(
                    TerminalMouseEvent(
                        action: .release(.left),
                        position: TerminalCellPoint(column: 1, row: 2)
                    )
                )
            )
        )
        let third = try #require(
            try runtime.renderIfDue(
                at: .zero.advanced(by: .nanoseconds(FrameScheduler.minimumFrameInterval.nanoseconds * 2))
            )
        )
        #expect(third.semantics.node(withID: "title")?.label == "Twice")
        #expect(runtime.graph.focusableNodes().first?.id == buttonID)
    }

    @Test("Primitive paint receives inherited and locally overridden environment values")
    func primitivePaintEnvironment() throws {
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session)
        let runtime = Runtime(
            view: PaintEnvironmentRoot(),
            presenter: presenter,
            terminalSize: CellSize(width: 2, height: 1),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()

        _ = try #require(try runtime.renderIfDue(at: .zero))

        #expect(surfaceText(presenter) == "PO")
    }

    @Test("Declarative view observes an animation transaction")
    func declarativeViewAnimationTransaction() throws {
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: view, session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        withAnimation(.linear(duration: .milliseconds(200))) {
            view.text = "b"
            runtime.invalidate(transaction: Transaction.current)
        }
        _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

        #expect(view.transactions.last?.animation == .linear(duration: .milliseconds(200)))
        #expect(runtime.graph.root?.value(as: String.self) == "b")
    }

    @Test("State mutation carries its animation transaction to the runtime")
    func stateMutationAnimationTransaction() throws {
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: AnimatedStateRoot(),
            presenter: presenter,
            terminalSize: CellSize(width: 10, height: 2),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .enter))))
        _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

        let animatedNode = try #require(
            firstNode(runtime.graph.root) {
                $0.presentationTarget(for: PresentationProperties.opacity) == 0.5
            }
        )
        #expect(animatedNode.animationStatus(for: .opacity) == .running)
    }

    @Test("Idle runtime has no next deadline")
    func idleDeadlineIsNil() throws {
        let runtime = makeRuntime(view: TestRuntimeView(text: "a"), session: FakeTerminalSession())
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        #expect(runtime.nextDeadline(at: .zero) == nil)
    }

    @Test("Concurrent invalidation channel coalesces regions and enters the UI executor")
    func concurrentInvalidationChannel() async throws {
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 4, height: 1),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        let channel = runtime.invalidationChannel

        try await Task.detached {
            try channel.send(.region(CellRect(x: 1, y: 0, width: 1, height: 1)))
            try channel.send(.region(CellRect(x: 2, y: 0, width: 1, height: 1)))
        }.value

        let result = try #require(
            try runtime.renderIfDue(
                at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)
            )
        )
        #expect(result.presentation.stats.scannedCellCount == 2)
        #expect(result.presentation.stats.changedCellCount == 0)
    }

    @Test("Animation timeline uses runtime instants and stays at or below sixty FPS")
    func animationTimelineRuntimeIntegration() throws {
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: TimelineView(.animation(minimumInterval: .milliseconds(1))) { context in
                Text(String(context.instant.nanoseconds), id: "timeline")
            },
            presenter: presenter,
            terminalSize: CellSize(width: 20, height: 1),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        let deadline = try #require(runtime.nextDeadline(at: .zero))
        #expect(deadline == .zero.advanced(by: FrameScheduler.minimumFrameInterval))
        #expect(try runtime.renderIfDue(at: .zero.advanced(by: .milliseconds(1))) == nil)
        _ = try runtime.renderIfDue(at: deadline)
        #expect(surfaceText(presenter).contains(String(deadline.nanoseconds)))
    }

    @Test("Periodic timeline requests its next absolute deadline and changes content")
    func periodicTimelineRuntimeIntegration() throws {
        let firstUpdate = TimeInstant.zero.advanced(by: .milliseconds(100))
        let secondUpdate = TimeInstant.zero.advanced(by: .milliseconds(200))
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: TimelineView(.periodic(from: .zero, by: .milliseconds(100))) { context in
                Text(context.instant < firstUpdate ? "idle" : "busy", id: "activity")
            },
            presenter: presenter,
            terminalSize: CellSize(width: 4, height: 1),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        #expect(runtime.nextDeadline(at: .zero) == firstUpdate)
        #expect(surfaceText(presenter) == "idle")
        _ = try runtime.renderIfDue(at: firstUpdate)
        #expect(surfaceText(presenter) == "busy")
        #expect(runtime.nextDeadline(at: firstUpdate) == secondUpdate)
    }

    @Test("Explicit timeline becomes idle after its last entry")
    func explicitTimelineEndsIdle() throws {
        let firstUpdate = TimeInstant.zero.advanced(by: .milliseconds(10))
        let secondUpdate = TimeInstant.zero.advanced(by: .milliseconds(20))
        let runtime = Runtime(
            view: TimelineView(.explicit([firstUpdate, secondUpdate])) { context in
                Text(String(context.instant.nanoseconds))
            },
            presenter: FramePresenter(session: FakeTerminalSession()),
            terminalSize: CellSize(width: 20, height: 1),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        #expect(runtime.nextDeadline(at: .zero) == firstUpdate)

        _ = try runtime.renderIfDue(at: firstUpdate)
        #expect(runtime.nextDeadline(at: firstUpdate) == secondUpdate)
        _ = try runtime.renderIfDue(at: secondUpdate)
        #expect(runtime.nextDeadline(at: secondUpdate) == nil)
    }

    @Test("Reduced motion timeline renders a static fallback and stays idle")
    func reducedMotionTimelineIsStatic() throws {
        let instant = TimeInstant.zero.advanced(by: .milliseconds(250))
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = Runtime(
            view: TimelineView(.animation()) { context in
                Text(context.isReducedMotionEnabled ? "static" : "moving")
            },
            presenter: presenter,
            terminalSize: CellSize(width: 6, height: 1),
            motionPolicy: .reduced,
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: instant)

        #expect(surfaceText(presenter) == "static")
        #expect(runtime.nextDeadline(at: instant) == nil)
    }

    @Test("An unchanged invalidated runtime frame does not write")
    func unchangedInvalidationDoesNotWrite() throws {
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: TestRuntimeView(text: "a"), session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        runtime.invalidate()
        let rendered = try runtime.renderIfDue(
            at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)
        )
        let result = try #require(rendered)

        #expect(result.presentation.didWrite == false)
        #expect(result.presentation.stats.wasFullRepaint == false)
        #expect(result.stats.encodedByteCount == 0)
        #expect(result.stats.damagedCellCount == 1)
        #expect(result.stats.changedCellCount == 0)
        #expect(result.stats.writeDuration == .zero)
        #expect(result.stats.internerByteCount > 0)
        #expect(session.presentationCount == 1)
    }

    @Test("Runtime frame stats contain measured stages and counters")
    func runtimeFrameStats() throws {
        let session = FakeTerminalSession()
        let runtimeTime = SteppedTimeSource(step: .nanoseconds(2))
        let presenterTime = SteppedTimeSource(step: .nanoseconds(3))
        let runtime = Runtime(
            view: TestRuntimeView(text: "a", animation: .linear(duration: .seconds(1))),
            presenter: FramePresenter(session: session, timeSource: presenterTime),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: runtimeTime
        )
        try runtime.start()

        let rendered = try runtime.renderIfDue(at: .zero)
        let result = try #require(rendered)

        #expect(result.stats == result.presentation.stats)
        #expect(result.stats.frameDuration == .nanoseconds(8))
        #expect(result.stats.reconciliationDuration == .nanoseconds(2))
        #expect(result.stats.layoutDuration == .nanoseconds(2))
        #expect(result.stats.paintDuration == .nanoseconds(2))
        #expect(result.stats.diffDuration == .nanoseconds(3))
        #expect(result.stats.writeDuration == .nanoseconds(3))
        #expect(result.stats.encodedByteCount > 0)
        #expect(result.stats.damagedCellCount == 1)
        #expect(result.stats.missedBudgetCount == 0)
        #expect(result.stats.activeAnimationCount == 0)
        #expect(runtime.nextDeadline(at: .zero) != nil)
        #expect(result.stats.internerByteCount > 0)
    }

    @Test("Missed frame budgets accumulate")
    func missedFrameBudgetsAccumulate() throws {
        let session = FakeTerminalSession()
        let timeSource = SteppedTimeSource(step: .milliseconds(5))
        let runtime = Runtime(
            view: TestRuntimeView(text: "a", animation: .linear(duration: .seconds(1))),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: timeSource
        )
        try runtime.start()
        let firstFrame = try runtime.renderIfDue(at: .zero)
        let secondFrame = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
        let first = try #require(firstFrame)
        let second = try #require(secondFrame)

        #expect(first.stats.frameDuration == .milliseconds(20))
        #expect(first.stats.missedBudgetCount == 1)
        #expect(second.stats.missedBudgetCount == 2)
    }

    @Test("Invalidations coalesce without stale frames")
    func invalidationsCoalesce() throws {
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: view, session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        view.text = "b"

        runtime.invalidate()
        runtime.invalidate()
        let early = try runtime.renderIfDue(at: .zero)
        let due = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
        let stale = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

        #expect(early == nil)
        #expect(due != nil)
        #expect(stale == nil)
        #expect(view.paintCount == 2)
    }

    @Test("Resize forces a full repaint")
    func resizeForcesFullRepaint() throws {
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: view, session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        try runtime.process(.resize(CellSize(width: 3, height: 1)))
        let rendered = try runtime.renderIfDue(
            at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)
        )
        let result = try #require(rendered)

        #expect(result.presentation.stats.wasFullRepaint)
        #expect(result.presentation.stats.scannedCellCount == 3)
        #expect(result.presentation.stats.damagedCellCount == 3)
        #expect(view.sizes.last == CellSize(width: 3, height: 1))
    }

    @Test("Resume forces a full repaint")
    func resumeForcesFullRepaint() throws {
        let runtime = makeRuntime(view: TestRuntimeView(text: "a"), session: FakeTerminalSession())
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        try runtime.suspend()
        try runtime.resume()

        let rendered = try runtime.renderIfDue(
            at: .zero.advanced(by: FrameScheduler.minimumFrameInterval)
        )
        let result = try #require(rendered)

        #expect(result.presentation.stats.wasFullRepaint)
    }

    @Test("Reduced motion samples the final state and stays idle")
    func reducedMotionIsFinalAndStatic() throws {
        let animation = Animation.linear(duration: .seconds(1))
        let view = TestRuntimeView(text: "a", animation: animation)
        let runtime = makeRuntime(
            view: view,
            session: FakeTerminalSession(),
            motionPolicy: .reduced
        )
        try runtime.start()

        _ = try runtime.renderIfDue(at: .zero)

        #expect(view.samples == [1])
        #expect(view.transactions.last?.areAnimationsEnabled == true)
        #expect(view.transactions.last?.isReducedMotionEnabled == true)
        #expect(runtime.nextDeadline(at: .zero) == nil)
    }

    @Test("Input and signal callbacks run on the runtime state machine")
    func callbacksAndSignalLifecycle() throws {
        var inputs: [TerminalInputEvent] = []
        var signals: [TerminalSignalEvent] = []
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let processControl = FakeRuntimeProcessControl()
        let presenter = FramePresenter(session: session)
        let runtime = Runtime(
            view: view,
            presenter: presenter,
            terminalSize: CellSize(width: 1, height: 1),
            processControl: processControl,
            onInput: { inputs.append($0) },
            onSignal: { event, _ in signals.append(event) }
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        let input = TerminalInputEvent.key(TerminalKeyEvent(key: .enter))

        try runtime.process(.input(input))
        try runtime.process(RuntimeEvent.signal(.suspend))
        try runtime.process(RuntimeEvent.signal(.resume))

        #expect(inputs == [input])
        #expect(signals == [.suspend, .resume])
        #expect(runtime.state == .running)
        #expect(runtime.nextDeadline(at: .zero) != nil)
        #expect(processControl.suspendCallCount == 1)
        #expect(session.events.prefix(2) == [.suspend, .resume])
    }

    @Test("Run waits off the main actor and dispatches parsed input")
    func eventSourceRunLoop() async throws {
        var inputs: [TerminalInputEvent] = []
        let session = FakeTerminalSession()
        session.inputBytes = Array("q".utf8)
        let eventSource = FakeRuntimeEventSource(events: [.inputReady, .signal(.terminate)])
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: DeterministicTimeSource(),
            eventSource: eventSource,
            onInput: { inputs.append($0) }
        )

        try await runtime.run()

        #expect(inputs == [.key(TerminalKeyEvent(key: .text("q")))])
        #expect(runtime.state == .stopped)
        #expect(session.state == .inactive)
        #expect(eventSource.timeouts.count == 2)
        #expect(eventSource.timeouts[0] == nil)
    }

    @Test("Cancellation stops the runtime and restores the terminal session", .timeLimit(.minutes(1)))
    func cancellationStopsRuntime() async throws {
        let session = FakeTerminalSession()
        let eventSource = FakeRuntimeEventSource()
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            eventSource: eventSource
        )
        let runTask = Task { try await runtime.run() }

        try await eventSource.waitForWaitCount(1)
        runTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await runTask.value
        }
        #expect(runtime.state == .stopped)
        #expect(session.state == .inactive)
        #expect(session.stopCount == 1)
    }

    @Test("Runtime startup applies a synchronized-output response")
    func startupProbesSynchronizedOutput() async throws {
        let session = FakeTerminalSession(synchronizedOutput: .unknown)
        session.inputBytes = Array("\u{1B}[?2026;1$y".utf8)
        let eventSource = FakeRuntimeEventSource(events: [.inputReady, .signal(.terminate)])
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: DeterministicTimeSource(),
            eventSource: eventSource
        )

        try await runtime.run()

        #expect(session.physicalWrites.first == SynchronizedOutputProbe.query)
        #expect(session.capabilities.synchronizedOutput == .supported)
        #expect(runtime.diagnostics.isEmpty)
    }

    @Test("A synchronized-output timeout selects fallback and records a diagnostic")
    func startupProbeTimeoutFallsBack() async throws {
        let session = FakeTerminalSession(synchronizedOutput: .unknown)
        let eventSource = FakeRuntimeEventSource(events: [nil, .signal(.terminate)])
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: DeterministicTimeSource(),
            eventSource: eventSource
        )

        try await runtime.run()

        #expect(session.capabilities.synchronizedOutput == .unsupported)
        #expect(runtime.diagnostics == [.synchronizedOutputProbe(.timedOut)])
    }

    @Test("A mandatory synchronized-output timeout throws a typed error")
    func mandatoryStartupProbeTimeoutThrows() async throws {
        let session = FakeTerminalSession(synchronizedOutput: .unknown)
        let eventSource = FakeRuntimeEventSource(events: [nil])
        let policy = TerminalProbePolicy(timeout: .milliseconds(50), timeoutRequirement: .mandatory)
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: DeterministicTimeSource(),
            eventSource: eventSource,
            terminalProbePolicy: policy
        )

        do {
            try await runtime.run()
            Issue.record("Expected a mandatory capability timeout")
        } catch let error as TerminalCapabilityProbeError {
            #expect(error == .synchronizedOutputTimedOut(timeout: .milliseconds(50)))
        }
        #expect(runtime.diagnostics.isEmpty)
        #expect(session.state == .inactive)
    }

    @Test(
        "Unsupported and oversized synchronized-output responses select fallback",
        arguments: [
            (Array("\u{1B}[?2026;0$y".utf8), SynchronizedOutputProbeResult.unsupported),
            (Array(repeating: UInt8(ascii: "x"), count: 33), .responseTooLarge(limit: 32)),
        ]
    )
    func startupProbeResponseFallsBack(
        bytes: [UInt8],
        expectedResult: SynchronizedOutputProbeResult
    ) async throws {
        let session = FakeTerminalSession(synchronizedOutput: .unknown)
        session.inputBytes = bytes
        let eventSource = FakeRuntimeEventSource(events: [.inputReady, .signal(.terminate)])
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: DeterministicTimeSource(),
            eventSource: eventSource,
            terminalProbePolicy: TerminalProbePolicy(maximumResponseByteCount: 32)
        )

        try await runtime.run()

        #expect(session.capabilities.synchronizedOutput == .unsupported)
        #expect(runtime.diagnostics == [.synchronizedOutputProbe(expectedResult)])
    }

    @Test("Idle invalidation wakes the runtime without a timer", .timeLimit(.minutes(1)))
    func idleInvalidationWakesRuntime() async throws {
        let session = FakeTerminalSession()
        let view = TestRuntimeView(text: "a")
        let eventSource = FakeRuntimeEventSource()
        let timeSource = MutableRuntimeTimeSource()
        let runtime = Runtime(
            view: view,
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: timeSource,
            eventSource: eventSource
        )
        let runTask = Task { try await runtime.run() }

        try await eventSource.waitForWaitCount(1)
        #expect(eventSource.timeouts == [nil])
        view.text = "b"
        runtime.invalidate()
        try await eventSource.waitForWaitCount(2)
        timeSource.advance(by: FrameScheduler.minimumFrameInterval)
        try eventSource.wake()
        try await eventSource.waitForWaitCount(3)
        #expect(view.paintCount == 2)
        #expect(eventSource.timeouts.count == 3)
        #expect(eventSource.timeouts[0] == nil)
        #expect(eventSource.timeouts[1] != nil)
        #expect(eventSource.timeouts[2] == nil)

        try runtime.stop()
        try await runTask.value
    }

    @Test("Input closure stops and restores the runtime once")
    func inputClosureStopsRuntimeOnce() async throws {
        let session = FakeTerminalSession()
        let eventSource = FakeRuntimeEventSource(events: [.inputClosed])
        let runtime = Runtime(
            view: TestRuntimeView(text: "a"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            eventSource: eventSource
        )

        try await runtime.run()

        #expect(runtime.state == .stopped)
        #expect(session.stopCount == 1)
        #expect(eventSource.timeouts.count == 1)
    }

    @Test("A frame failure stops and cleans up the terminal session")
    func frameFailureCleansUpSession() throws {
        let session = FakeTerminalSession()
        let runtime = Runtime(
            view: FailingRuntimeView(),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()

        #expect(throws: RuntimeViewTestError.expected) {
            try runtime.renderIfDue(at: .zero)
        }

        #expect(runtime.state == .stopped)
        #expect(session.state == .inactive)
        #expect(runtime.graph.root == nil)
        #expect(runtime.graph.revision == 0)
    }

    @Test("A layout failure rolls back the staged graph and lifecycle")
    func layoutFailureRollsBackGraph() throws {
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: view, session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        let committedRoot = try #require(runtime.graph.root)
        let committedRevision = runtime.graph.revision
        view.text = "b"
        view.layoutError = .expected
        runtime.invalidate()

        #expect(throws: RuntimeViewTestError.expected) {
            try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
        }

        #expect(runtime.graph.root === committedRoot)
        #expect(runtime.graph.root?.value(as: String.self) == "a")
        #expect(runtime.graph.revision == committedRevision)
        #expect(view.mountCount == 1)
        #expect(view.updateCount == 0)
    }

    @Test("A paint failure rolls back the staged graph and lifecycle")
    func paintFailureRollsBackGraph() throws {
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: view, session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        let committedRoot = try #require(runtime.graph.root)
        let committedRevision = runtime.graph.revision
        view.text = "b"
        view.paintError = .expected
        runtime.invalidate()

        #expect(throws: RuntimeViewTestError.expected) {
            try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
        }

        #expect(runtime.graph.root === committedRoot)
        #expect(runtime.graph.root?.value(as: String.self) == "a")
        #expect(runtime.graph.revision == committedRevision)
        #expect(view.mountCount == 1)
        #expect(view.updateCount == 0)
    }

    @Test("A presentation failure rolls back the staged graph and lifecycle")
    func presentationFailureRollsBackGraph() throws {
        let view = TestRuntimeView(text: "a")
        let session = FakeTerminalSession()
        let runtime = makeRuntime(view: view, session: session)
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        let committedRoot = try #require(runtime.graph.root)
        let committedRevision = runtime.graph.revision
        view.text = "b"
        session.presentationError = .expected
        runtime.invalidate()

        #expect(throws: FakeTerminalSession.PresentationError.expected) {
            try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
        }

        #expect(runtime.graph.root === committedRoot)
        #expect(runtime.graph.root?.value(as: String.self) == "a")
        #expect(runtime.graph.revision == committedRevision)
        #expect(view.mountCount == 1)
        #expect(view.updateCount == 0)
    }

    private func makeRuntime(
        view: TestRuntimeView,
        session: FakeTerminalSession,
        motionPolicy: MotionPolicy = .standard
    ) -> Runtime {
        Runtime(
            view: view,
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: 1, height: 1),
            motionPolicy: motionPolicy,
            timeSource: DeterministicTimeSource()
        )
    }

    private func surfaceText(_ presenter: FramePresenter) -> String {
        guard let surface = presenter.frontSurface else { return "" }
        return (0..<surface.size.height).map { y in
            (0..<surface.size.width).compactMap { x in
                let cell = surface[CellPoint(x: x, y: y)]
                guard cell.isContinuation == false else { return nil }
                return presenter.resources.graphemes.value(for: cell.graphemeID)
            }.joined()
        }.joined(separator: "\n")
    }

    private func cellPoint(for grapheme: String, in presenter: FramePresenter) -> CellPoint? {
        guard let surface = presenter.frontSurface else { return nil }
        for y in 0..<surface.size.height {
            for x in 0..<surface.size.width {
                let point = CellPoint(x: x, y: y)
                let cell = surface[point]
                if cell.isContinuation == false,
                    presenter.resources.graphemes.value(for: cell.graphemeID) == grapheme
                {
                    return point
                }
            }
        }
        return nil
    }

    private func foregroundRGBA(at point: CellPoint, presenter: FramePresenter) -> RGBA? {
        guard let surface = presenter.frontSurface,
            let style = presenter.resources.styles.value(for: surface[point].styleID),
            case .rgba(let color)? = style.foreground
        else { return nil }
        return color
    }

    private func firstNode(_ node: MountedNode?, matching predicate: (MountedNode) -> Bool) -> MountedNode? {
        guard let node else { return nil }
        if predicate(node) { return node }
        for child in node.children {
            if let match = firstNode(child, matching: predicate) { return match }
        }
        return nil
    }
}

@MainActor
private struct TerminalSizeProbe: View {
    @Environment(TerminalSizeEnvironmentKey.self) private var terminalSize

    var graphBody: [NodeDescriptor] {
        Text("\(terminalSize.width)x\(terminalSize.height)").graphBody
    }
}

@MainActor
private final class RuntimeCommandRecorder {
    var invocations = 0
}

@MainActor
private final class RuntimeProgressModel {
    var value: Double

    init(value: Double) {
        self.value = value
    }

    var binding: Binding<Double> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

@MainActor
private final class RuntimePromptModel {
    var document: PromptDocument

    init(document: PromptDocument = PromptDocument(text: "Runtime")) {
        self.document = document
    }

    var binding: Binding<PromptDocument> {
        Binding(get: { self.document }, set: { self.document = $0 })
    }
}

@MainActor
private final class RuntimePromptTransitionModel {
    var document = PromptDocument(text: "Runtime")
    var configuration: AgentPromptConfiguration

    init(animationsEnabled: Bool = true) {
        configuration = AgentPromptConfiguration(animationsEnabled: animationsEnabled)
    }
}

@MainActor
private struct RuntimePromptTransitionRoot: View {
    let model: RuntimePromptTransitionModel

    var graphBody: [NodeDescriptor] {
        AgentPrompt<String>(
            Binding(get: { model.document }, set: { model.document = $0 }),
            configuration: model.configuration,
            actions: AgentPromptActions(submit: { _ in }, cancel: {}, paste: { _ in }, attach: { _ in })
        ).graphBody
    }
}

@MainActor
private final class RuntimePromptRecorder {
    var submitted: [PromptDocument] = []
    var pasted: [String] = []
    var diagnostics: [AgentPromptDiagnostic] = []
    var cancelCount = 0
}

@MainActor
private final class RuntimeViewportModel {
    var state = ConversationViewportState(
        viewportExtent: 1,
        itemExtent: 1,
        itemCount: 3,
        initiallyPinnedToBottom: false
    )
    var forwardCount = 0
}

@MainActor
private final class RuntimeAutocompleteModel {
    var insertions: [PromptInsertion] = []
}

private var runtimeAgentTheme: ResolvedSemanticTheme {
    ResolvedSemanticTheme(
        scheme: .dark,
        colors: Dictionary(uniqueKeysWithValues: SemanticColorRole.allCases.map { ($0, .white) })
    )
}

@MainActor
private final class RuntimeAgentComponentModel {
    var diagnosticsState = DiagnosticsListState()
    var focusedAttachments: [Int] = []
    var removedAttachments: [Int] = []
    var reasoningToggleCount = 0
    var toolFailureIDs: [Int] = []
    var shellToggleCount = 0
    var navigatedDiagnosticIDs: [Int] = []
    var sidebarDismissCount = 0
}

@MainActor
private struct RuntimeAgentComponentRoot: View {
    let model: RuntimeAgentComponentModel

    var graphBody: [NodeDescriptor] {
        VStack(alignment: .leading) {
            AgentComponentView(
                AttachmentChip(id: 7, kind: .file, name: "file"),
                actions: AttachmentChipActions(
                    focus: { model.focusedAttachments.append($0) },
                    remove: { model.removedAttachments.append($0) }
                ),
                theme: runtimeAgentTheme
            )
            AgentComponentView(
                ReasoningDisclosure(phase: .completed, body: "body"),
                actions: ReasoningDisclosureActions { model.reasoningToggleCount += 1 },
                theme: runtimeAgentTheme
            )
            AgentComponentView(
                ToolCallRow(id: 9, label: "Build", state: .failed, errorBody: "Exit 1"),
                actions: ToolCallRowActions { model.toolFailureIDs.append($0) },
                theme: runtimeAgentTheme
            )
            AgentComponentView(
                ShellResult(command: "test", output: "1\n2\n3\n4\n5"),
                actions: ShellResultActions { model.shellToggleCount += 1 },
                theme: runtimeAgentTheme,
                viewportWidth: 40
            )
            AgentComponentView(
                DiagnosticsList(diagnostics: [
                    DiagnosticPresentation(id: 1, severity: .warning, message: "one"),
                    DiagnosticPresentation(id: 2, severity: .error, message: "two"),
                ]),
                state: Binding(
                    get: { model.diagnosticsState },
                    set: { model.diagnosticsState = $0 }
                ),
                actions: DiagnosticsListActions { model.navigatedDiagnosticIDs.append($0) },
                theme: runtimeAgentTheme
            )
            AgentComponentView(
                SessionSidebar(
                    sections: [SessionSidebarSection(kind: .files, title: "Files", items: ["file"])],
                    isOverlayPresented: true
                ),
                actions: SessionSidebarActions { model.sidebarDismissCount += 1 },
                theme: runtimeAgentTheme
            )
        }.graphBody
    }
}

@MainActor
private final class RuntimePermissionModel {
    var prompt = PermissionPrompt(
        requestedAction: "Write",
        risk: .elevated,
        choices: [
            PermissionChoice(scope: .deny, label: "Deny", risk: .low),
            PermissionChoice(scope: .once, label: "Allow once", risk: .elevated),
        ]
    )
    var choices: [PermissionChoice] = []
}

@MainActor
private struct RuntimePermissionRoot: View {
    let model: RuntimePermissionModel

    var graphBody: [NodeDescriptor] {
        AgentComponentView(
            Binding(get: { model.prompt }, set: { model.prompt = $0 }),
            actions: PermissionPromptActions { model.choices.append($0) },
            theme: runtimeAgentTheme
        ).graphBody
    }
}

@MainActor
private final class RuntimeQuestionModel {
    var prompt = QuestionPrompt(questions: [
        Question(
            id: "mode",
            title: "Mode",
            kind: .singleSelection,
            options: [QuestionOption(id: "a", label: "A"), QuestionOption(id: "b", label: "B")],
            validationRules: [.required]
        ),
        Question(id: "note", title: "Note", kind: .customText, validationRules: [.required]),
    ])
    var state = QuestionPromptState(focusedOptionIndex: 0)
    var submissions: [[String: QuestionAnswer]] = []
    var cancelCount = 0
}

@MainActor
private struct RuntimeQuestionRoot: View {
    let model: RuntimeQuestionModel

    var graphBody: [NodeDescriptor] {
        AgentComponentView(
            Binding(get: { model.prompt }, set: { model.prompt = $0 }),
            state: Binding(get: { model.state }, set: { model.state = $0 }),
            actions: QuestionPromptActions(
                submit: { model.submissions.append($0) },
                cancel: { model.cancelCount += 1 }
            ),
            theme: runtimeAgentTheme
        ).graphBody
    }
}

@MainActor
private struct DeclarativeTestRoot: View {
    @State private var activationCount = 0

    var graphBody: [NodeDescriptor] {
        buildViewGraph {
            VStack(alignment: .leading) {
                Text(["界", "Done", "Twice"][min(activationCount, 2)], id: "title")
                Button("Run", id: "action") { activationCount += 1 }
                RichText(StyledText("Rich"), id: "rich")
                AgentComponentView(
                    ToastPresentation(kind: .info, message: "Agent"),
                    theme: ResolvedSemanticTheme(
                        scheme: .dark,
                        colors: Dictionary(uniqueKeysWithValues: SemanticColorRole.allCases.map { ($0, .white) })
                    )
                )
            }
            .padding(1)
            .frame(width: 16, height: 8, alignment: .topLeading)
        }
    }
}

private enum RuntimePaintValueKey: EnvironmentKey, PaintEnvironmentKey {
    static let defaultValue = "D"
}

@MainActor
private struct PaintEnvironmentRoot: View {
    var graphBody: [NodeDescriptor] {
        HStack(spacing: 0) {
            EnvironmentPaintView()
            EnvironmentPaintView().environment(RuntimePaintValueKey.self, value: "O")
        }
        .environment(RuntimePaintValueKey.self, value: "P")
        .graphBody
    }
}

@MainActor
private struct EnvironmentPaintView: View {
    var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: EnvironmentPaintPrimitive())]
    }
}

private struct EnvironmentPaintPrimitive: SemanticRenderable {
    func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: 1, height: 1)
    }

    func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let value = context.environment[RuntimePaintValueKey.self]
        let grapheme = try resources.graphemes.intern(Character(value))
        _ = try surface.write(graphemeID: grapheme, at: context.origin, clip: context.clip)
        return SemanticNode(
            id: SemanticID(rawValue: value),
            role: .text,
            frame: CellRect(origin: context.origin, size: CellSize(width: 1, height: 1))
        )
    }
}

@MainActor
private struct AnimatedStateRoot: View {
    @State private var isDimmed = false

    var graphBody: [NodeDescriptor] {
        Button("Animate") {
            withAnimation(.linear(duration: .milliseconds(200))) {
                isDimmed.toggle()
            }
        }
        .opacity(isDimmed ? 0.5 : 1)
        .graphBody
    }
}

private enum RuntimeViewTestError: Error {
    case expected
}

@MainActor
private struct FailingRuntimeView: RuntimeView {
    func nodeDescriptor(in context: RuntimeFrameContext) -> NodeDescriptor {
        NodeDescriptor(type: FailingRuntimeView.self)
    }

    func paint(
        in context: RuntimeFrameContext,
        resources: inout ControlRenderResources
    ) throws -> RuntimeFrame {
        throw RuntimeViewTestError.expected
    }
}

// NSCondition protects every mutable field and serializes blocking waits.
private final class FakeRuntimeEventSource: RuntimeEventSource, @unchecked Sendable {
    private let condition = NSCondition()
    private var events: [TerminalRuntimeEvent?]
    private var recordedTimeouts: [TimeSpan?] = []
    private var wakeIsPending = false

    init(events: [TerminalRuntimeEvent?] = []) {
        self.events = events
    }

    var timeouts: [TimeSpan?] {
        condition.withLock { recordedTimeouts }
    }

    func nextEvent(timeout: TimeSpan?) throws -> TerminalRuntimeEvent? {
        condition.lock()
        defer { condition.unlock() }
        recordedTimeouts.append(timeout)
        condition.broadcast()
        if events.isEmpty == false {
            return events.removeFirst()
        }
        if wakeIsPending {
            wakeIsPending = false
            return .wake
        }
        guard let timeout else {
            while events.isEmpty, wakeIsPending == false {
                condition.wait()
            }
            if events.isEmpty == false {
                return events.removeFirst()
            }
            wakeIsPending = false
            return .wake
        }
        guard timeout > .zero else { return nil }
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while events.isEmpty, wakeIsPending == false, condition.wait(until: deadline) {}
        if events.isEmpty == false {
            return events.removeFirst()
        }
        guard wakeIsPending else { return nil }
        wakeIsPending = false
        return .wake
    }

    func wake() throws {
        condition.withLock {
            wakeIsPending = true
            condition.broadcast()
        }
    }

    func waitForWaitCount(_ count: Int) async throws {
        try await Task.detached { [self] in try waitForWaitCountBlocking(count) }.value
    }

    private func waitForWaitCountBlocking(_ count: Int) throws {
        let deadline = Date().addingTimeInterval(10)
        condition.lock()
        defer { condition.unlock() }
        while recordedTimeouts.count < count {
            guard condition.wait(until: deadline) else {
                throw FakeRuntimeEventSourceError.timedOut
            }
        }
    }
}

private enum FakeRuntimeEventSourceError: Error {
    case timedOut
}

private final class MutableRuntimeTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current = TimeInstant.zero

    var now: TimeInstant {
        lock.withLock { current }
    }

    func advance(by duration: TimeSpan) {
        lock.withLock { current = current.advanced(by: duration) }
    }
}

// NSLock protects the mutable call counter.
private final class FakeRuntimeProcessControl: RuntimeProcessControl, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var suspendCallCount: Int {
        lock.withLock { callCount }
    }

    func suspendCurrentProcess() throws {
        lock.withLock { callCount += 1 }
    }
}

@MainActor
private final class TestRuntimeView: RuntimeView {
    var text: String
    let animation: Animation?
    var layoutError: RuntimeViewTestError?
    var paintError: RuntimeViewTestError?
    private(set) var paintCount = 0
    private(set) var sizes: [CellSize] = []
    private(set) var transactions: [Transaction] = []
    private(set) var samples: [Double] = []
    private(set) var mountCount = 0
    private(set) var updateCount = 0

    init(text: String, animation: Animation? = nil) {
        self.text = text
        self.animation = animation
        layoutError = nil
        paintError = nil
    }

    func nodeDescriptor(in context: RuntimeFrameContext) -> NodeDescriptor {
        NodeDescriptor(
            type: TestRuntimeView.self,
            value: text,
            lifecycle: NodeLifecycle(
                onMount: { [self] _ in mountCount += 1 },
                onUpdate: { [self] _ in updateCount += 1 }
            )
        )
    }

    func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws {
        if let layoutError {
            throw layoutError
        }
        graph.root?.cache(
            size: context.terminalSize,
            frame: CellRect(origin: .zero, size: context.terminalSize)
        )
    }

    func paint(
        in context: RuntimeFrameContext,
        resources: inout ControlRenderResources
    ) throws -> RuntimeFrame {
        if let paintError {
            throw paintError
        }
        paintCount += 1
        sizes.append(context.terminalSize)
        transactions.append(context.transaction)
        var surface = Surface(size: context.terminalSize)
        if let character = text.first, context.terminalSize.isEmpty == false {
            let identifier = try resources.graphemes.intern(character)
            _ = try surface.write(graphemeID: identifier, at: .zero)
        }
        if let animation {
            samples.append(context.sample(animation, startedAt: .zero).value)
        }
        return RuntimeFrame(
            surface: surface,
            nextFrameCadence: animation == nil ? nil : FrameScheduler.minimumFrameInterval
        )
    }
}
