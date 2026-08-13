//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppRunnerTests.swift
//
//  License: MIT

import TUIkitTestSupport
import Testing

@testable import TUIkit

@MainActor
@Suite("AppRunner Tests", .serialized)
struct AppRunnerTests {
    @Test("App runner drains InputEvent values")
    func drainsInputEvents() async throws {
        let eventChannel = RuntimeEventChannel()
        let terminal = MockTerminal()
        terminal.inputEventQueue = [.key(KeyEvent(character: "q"))]
        eventChannel.send(.inputAvailable)
        let runner = AppRunner(
            app: InputDrainApp(),
            terminal: terminal,
            tuiContext: TUIContext(),
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(terminal.inputEventQueue.isEmpty)
    }

    @Test("App runner reschedules buffered input one event at a time")
    func reschedulesBufferedInput() async throws {
        let eventChannel = RuntimeEventChannel()
        let terminal = MockTerminal()
        terminal.inputEventQueue =
            Array(
                repeating: .key(KeyEvent(character: "a")),
                count: 3
            ) + [.key(KeyEvent(character: "q"))]
        eventChannel.send(.inputAvailable)
        let runner = AppRunner(
            app: InputDrainApp(),
            terminal: terminal,
            tuiContext: TUIContext(),
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(terminal.inputEventQueue.isEmpty)
    }

    @Test("App runner yields before remaining buffered input")
    func yieldsBeforeRemainingBufferedInput() async throws {
        let eventChannel = RuntimeEventChannel()
        let terminal = MockTerminal()
        terminal.inputEventQueue = Array(
            repeating: .key(KeyEvent(character: "a")),
            count: 3
        )
        eventChannel.send(.inputAvailable)
        let runner = AppRunner(
            app: FirstInputShutdownApp(eventChannel: eventChannel),
            terminal: terminal,
            tuiContext: TUIContext(),
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(terminal.inputEventQueue.count == 2)
    }

    @Test("App runner renders before queued repeat input")
    func rendersBeforeQueuedRepeatInput() async throws {
        let renderStates = TraceRecorder<Bool>()
        let eventChannel = RuntimeEventChannel()
        let context = TUIContext()
        let terminal = MockTerminal()
        terminal.inputEventQueue = [
            .key(KeyEvent(character: "a")),
            .key(KeyEvent(character: "a")),
            .key(KeyEvent(character: "q")),
        ]
        var didInjectReadiness = false
        terminal.onReadInputEvent = {
            guard !didInjectReadiness else { return }
            didInjectReadiness = true
            eventChannel.send(.inputAvailable)
        }
        eventChannel.send(.inputAvailable)
        let runner = AppRunner(
            app: RepeatInputApp(
                appState: context.appState,
                renderStates: renderStates,
                eventChannel: eventChannel
            ),
            terminal: terminal,
            tuiContext: context,
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(renderStates.snapshot() == [false, false])
    }

    @Test("Repeated render invalidation does not starve input", .timeLimit(.minutes(1)))
    func repeatedRenderInvalidationDoesNotStarveInput() async throws {
        let eventChannel = RuntimeEventChannel()
        let context = TUIContext()
        let terminal = MockTerminal()
        terminal.inputEventQueue = [.key(KeyEvent(character: "q"))]
        eventChannel.send(.inputAvailable)
        let runner = AppRunner(
            app: ContinuouslyInvalidatingApp(appState: context.appState),
            terminal: terminal,
            tuiContext: context,
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(terminal.inputEventQueue.isEmpty)
    }

    @Test("App runner retries an ambiguous input prefix", .timeLimit(.minutes(1)))
    func retriesAmbiguousInputPrefix() async throws {
        let eventChannel = RuntimeEventChannel()
        let terminal = MockTerminal()
        terminal.inputEventQueue = [.key(KeyEvent(character: "q"))]
        terminal.deferredInputReadCount = 1
        terminal.inputRetryDelay = .milliseconds(1)
        eventChannel.send(.inputAvailable)
        let runner = AppRunner(
            app: InputDrainApp(),
            terminal: terminal,
            tuiContext: TUIContext(),
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(terminal.inputEventQueue.isEmpty)
    }

    @Test("App runner yields the MainActor to view tasks before shutdown")
    func yieldsMainActorToViewTasks() async throws {
        let events = TraceRecorder<String>()
        let eventChannel = RuntimeEventChannel()
        let terminal = MockTerminal()
        let context = TUIContext()
        let runner = AppRunner(
            app: MainActorTaskApp(events: events, eventChannel: eventChannel),
            terminal: terminal,
            tuiContext: context,
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        try await runner.run()

        #expect(events.snapshot() == ["completed"])
    }

    @Test("Idle app does not request periodic renders", .timeLimit(.minutes(1)))
    func idleAppDoesNotRequestPeriodicRenders() async throws {
        let invalidations = TraceRecorder<String>()
        let taskStarted = AsyncSignal()
        let releaseTask = AsyncSignal()
        let eventChannel = RuntimeEventChannel()
        let context = TUIContext()
        context.appState.observe {
            invalidations.record("render")
        }
        let runner = AppRunner(
            app: IdleTaskApp(
                taskStarted: taskStarted,
                releaseTask: releaseTask,
                eventChannel: eventChannel
            ),
            terminal: MockTerminal(),
            tuiContext: context,
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        let runTask = Task {
            try await runner.run()
        }
        await taskStarted.wait()
        try await ContinuousClock().sleep(for: .milliseconds(250))
        releaseTask.signal()
        try await runTask.value

        #expect(invalidations.snapshot().isEmpty)
    }

    @Test("Terminal failures are thrown after terminal cleanup")
    func terminalFailureIsThrownAfterCleanup() async {
        let expectedFailure = TerminalIOFailure(
            operation: .write,
            errorCode: 5,
            remainingByteCount: 4
        )
        let terminal = MockTerminal()
        terminal.pendingIOFailure = expectedFailure
        let eventChannel = RuntimeEventChannel()
        let runner = AppRunner(
            app: MainActorTaskApp(events: TraceRecorder<String>(), eventChannel: eventChannel),
            terminal: terminal,
            tuiContext: TUIContext(),
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        do {
            try await runner.run()
            Issue.record("Expected the terminal failure to be thrown")
        } catch let failure as TerminalIOFailure {
            #expect(failure == expectedFailure)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!terminal.isRawModeEnabled)
        #expect(!terminal.isCursorHidden)
        #expect(!terminal.isInAlternateScreen)
    }

    @Test("Shutdown cancels view tasks and restores the terminal", .timeLimit(.minutes(1)))
    func shutdownCancelsTasksAndRestoresTerminal() async throws {
        let taskStarted = AsyncSignal()
        let taskCancelled = AsyncSignal()
        let releaseTask = AsyncSignal()
        let eventChannel = RuntimeEventChannel()
        let terminal = MockTerminal()
        let runner = AppRunner(
            app: ShutdownTaskApp(
                taskStarted: taskStarted,
                taskCancelled: taskCancelled,
                releaseTask: releaseTask
            ),
            terminal: terminal,
            tuiContext: TUIContext(),
            eventChannel: eventChannel,
            inputSource: nil,
            signals: nil
        )

        let runTask = Task {
            try await runner.run()
        }
        await taskStarted.wait()
        eventChannel.send(.shutdownRequested)
        try await runTask.value
        await taskCancelled.wait()

        #expect(!terminal.isRawModeEnabled)
        #expect(!terminal.isCursorHidden)
        #expect(!terminal.isInAlternateScreen)
    }
}

@MainActor
private struct InputDrainApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("Input")
        }
    }
}

@MainActor
private struct FirstInputShutdownApp: App {
    let eventChannel: RuntimeEventChannel

    init() {
        self.eventChannel = RuntimeEventChannel()
    }

    init(eventChannel: RuntimeEventChannel) {
        self.eventChannel = eventChannel
    }

    var body: some Scene {
        WindowGroup {
            Text("Input")
                .onKeyPress { _ in
                    eventChannel.send(.shutdownRequested)
                    return true
                }
        }
    }
}

@MainActor
private struct RepeatInputApp: App {
    let appState: AppState
    let renderStates: TraceRecorder<Bool>
    let eventChannel: RuntimeEventChannel

    init() {
        self.appState = AppState()
        self.renderStates = TraceRecorder<Bool>()
        self.eventChannel = RuntimeEventChannel()
    }

    init(
        appState: AppState,
        renderStates: TraceRecorder<Bool>,
        eventChannel: RuntimeEventChannel
    ) {
        self.appState = appState
        self.renderStates = renderStates
        self.eventChannel = eventChannel
    }

    var body: some Scene {
        WindowGroup {
            Text("Input")
                .onKeyPress { event in
                    if event.key == .character("q") {
                        eventChannel.send(.shutdownRequested)
                        return true
                    }
                    renderStates.record(appState.needsRender)
                    appState.setNeedsRender()
                    return true
                }
        }
    }
}

@MainActor
private struct ContinuouslyInvalidatingApp: App {
    let appState: AppState

    init() {
        self.appState = AppState()
    }

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some Scene {
        WindowGroup {
            ContinuouslyInvalidatingView(appState: appState)
        }
    }
}

private struct ContinuouslyInvalidatingView: View, Renderable {
    let appState: AppState

    var body: Never {
        fatalError("ContinuouslyInvalidatingView renders directly")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        appState.setNeedsRender()
        return FrameBuffer(text: "Input")
    }
}

@MainActor
private struct MainActorTaskApp: App {
    let events: TraceRecorder<String>
    let eventChannel: RuntimeEventChannel

    init() {
        self.events = TraceRecorder<String>()
        self.eventChannel = RuntimeEventChannel()
    }

    init(events: TraceRecorder<String>, eventChannel: RuntimeEventChannel) {
        self.events = events
        self.eventChannel = eventChannel
    }

    var body: some Scene {
        WindowGroup {
            Text("Task")
                .task {
                    await MainActor.run {
                        events.record("completed")
                        eventChannel.send(.shutdownRequested)
                    }
                }
        }
    }
}

@MainActor
private struct IdleTaskApp: App {
    let taskStarted: AsyncSignal
    let releaseTask: AsyncSignal
    let eventChannel: RuntimeEventChannel

    init() {
        self.taskStarted = AsyncSignal()
        self.releaseTask = AsyncSignal()
        self.eventChannel = RuntimeEventChannel()
    }

    init(
        taskStarted: AsyncSignal,
        releaseTask: AsyncSignal,
        eventChannel: RuntimeEventChannel
    ) {
        self.taskStarted = taskStarted
        self.releaseTask = releaseTask
        self.eventChannel = eventChannel
    }

    var body: some Scene {
        WindowGroup {
            Text("Idle")
                .task {
                    taskStarted.signal()
                    await releaseTask.wait()
                    eventChannel.send(.shutdownRequested)
                }
        }
    }
}

@MainActor
private struct ShutdownTaskApp: App {
    let taskStarted: AsyncSignal
    let taskCancelled: AsyncSignal
    let releaseTask: AsyncSignal

    init() {
        self.taskStarted = AsyncSignal()
        self.taskCancelled = AsyncSignal()
        self.releaseTask = AsyncSignal()
    }

    init(
        taskStarted: AsyncSignal,
        taskCancelled: AsyncSignal,
        releaseTask: AsyncSignal
    ) {
        self.taskStarted = taskStarted
        self.taskCancelled = taskCancelled
        self.releaseTask = releaseTask
    }

    var body: some Scene {
        WindowGroup {
            Text("Running")
                .task {
                    taskStarted.signal()
                    await withTaskCancellationHandler {
                        await releaseTask.wait()
                    } onCancel: {
                        taskCancelled.signal()
                    }
                }
        }
    }
}
