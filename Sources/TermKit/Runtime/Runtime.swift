#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Supplies terminal events to the runtime event loop.
public protocol RuntimeEventSource: Sendable {
    /// Returns the next event, or `nil` when the timeout expires.
    func nextEvent(timeout: TimeSpan?) throws -> TerminalRuntimeEvent?
    /// Wakes a blocked event read.
    func wake() throws
}

extension TerminalEventSource: RuntimeEventSource {}

/// Defines process operations required by the runtime.
public protocol RuntimeProcessControl: Sendable {
    /// Suspends the current process.
    func suspendCurrentProcess() throws
}

/// Describes an error from runtime process control.
public enum RuntimeProcessControlError: Error, Equatable, Sendable {
    /// A POSIX operation failed with the specified error code.
    case posix(errorCode: Int32)
}

/// Controls the current process through system calls.
public struct SystemRuntimeProcessControl: RuntimeProcessControl {
    /// Creates system process control.
    public init() {}

    /// Suspends the current process with `SIGSTOP`.
    public func suspendCurrentProcess() throws {
        guard kill(getpid(), SIGSTOP) == 0 else {
            throw RuntimeProcessControlError.posix(errorCode: errno)
        }
    }
}

/// Describes the runtime lifecycle state.
public enum RuntimeState: Sendable, Hashable {
    /// The runtime has not started.
    case inactive
    /// The runtime is processing events and frames.
    case running
    /// The runtime session is suspended.
    case suspended
    /// The runtime has stopped.
    case stopped
}

/// Describes a region that requires a new frame.
public enum RuntimeInvalidation: Sendable, Hashable {
    /// Invalidates the complete frame.
    case all
    /// Invalidates the specified cell region.
    case region(CellRect)
}

/// Describes an event that changes runtime state or content.
public enum RuntimeEvent: Sendable {
    /// Requests a frame invalidation with an optional transaction.
    case invalidate(RuntimeInvalidation, transaction: Transaction? = nil)
    /// Delivers a parsed terminal input event.
    case input(TerminalInputEvent)
    /// Updates the terminal size.
    case resize(CellSize)
    /// Delivers a terminal signal event.
    case signal(TerminalSignalEvent)
}

/// Describes an error produced by the runtime.
public enum RuntimeError: Error, Sendable, Equatable {
    /// The requested operation is not valid in the specified state.
    case invalidState(RuntimeState)
    /// The runtime cannot run without an event source.
    case eventSourceUnavailable
    /// A frame render started while another frame render was active.
    case reentrantFrame
    /// A rendered surface does not match the terminal size.
    case invalidSurfaceSize(expected: CellSize, actual: CellSize)
    /// An animation produced a nonfinite presentation value.
    case invalidPresentationValue(property: AnimationPropertyKey, value: String)
    /// Cleanup failed after an earlier runtime failure.
    case cleanupAfterFailure(primaryError: String, cleanupError: String)
}

/// A recoverable runtime diagnostic.
public enum RuntimeDiagnostic: Sendable, Equatable {
    /// The synchronized-output probe selected fallback presentation.
    case synchronizedOutputProbe(SynchronizedOutputProbeResult)
}

/// Contains the output and statistics for one rendered frame.
public struct RuntimeFrameResult: Sendable {
    /// The scheduler tick that initiated the frame.
    public var tick: FrameTick
    /// The terminal presentation result.
    public var presentation: PresenterResult
    /// The combined rendering statistics.
    public var stats: RenderStats
    /// The semantic tree for the frame.
    public var semantics: SemanticTree
    /// The view graph revision after the frame.
    public var graphRevision: UInt64

    /// Creates a frame result.
    public init(
        tick: FrameTick,
        presentation: PresenterResult,
        stats: RenderStats,
        semantics: SemanticTree,
        graphRevision: UInt64
    ) {
        self.tick = tick
        self.presentation = presentation
        self.stats = stats
        self.semantics = semantics
        self.graphRevision = graphRevision
    }
}

/// Coordinates terminal events, view updates, rendering, and presentation.
@MainActor
public final class Runtime {
    /// Handles a parsed terminal input event.
    public typealias InputHandler = @MainActor (_ event: TerminalInputEvent) throws -> Void
    /// Handles a terminal input parsing error.
    public typealias InputErrorHandler = @MainActor (_ error: TerminalInputParseError) -> Void
    /// Handles a terminal signal and its resulting action.
    public typealias SignalHandler =
        @MainActor (
            _ event: TerminalSignalEvent,
            _ action: TerminalSignalAction
        ) throws -> Void

    /// The current runtime lifecycle state.
    public private(set) var state: RuntimeState = .inactive
    /// The current terminal size in cells.
    public private(set) var terminalSize: CellSize
    /// The semantic tree from the last rendered frame.
    public private(set) var semantics = SemanticTree()
    /// Recoverable diagnostics recorded during execution.
    public private(set) var diagnostics: [RuntimeDiagnostic] = []
    /// The view graph managed by the runtime.
    public let graph: ViewGraph
    /// The scheduler that controls frame timing.
    public let scheduler: FrameScheduler
    /// The channel for invalidation requests from concurrent work.
    nonisolated public let invalidationChannel: RuntimeInvalidationChannel
    /// The motion policy for subsequent frames.
    public var motionPolicy: MotionPolicy
    /// The application commands that receive keyboard shortcuts before focused controls.
    public let commands: KeyboardCommandSet
    /// The optional handler for parsed input events.
    public var onInput: InputHandler?
    /// The optional handler for input parsing errors.
    public var onInputError: InputErrorHandler?
    /// The optional handler for terminal signals.
    public var onSignal: SignalHandler?

    private static let animationDemand: FrameDemandID = "runtime-view-animation"
    private static let timelineCadenceDemand: FrameDemandID = "runtime-view-timeline-cadence"
    private static let timelineDeadlineDemand: FrameDemandID = "runtime-view-timeline-deadline"

    private let view: any RuntimeView
    private let declarativeInputDispatcher: (@MainActor (_ event: TerminalInputEvent) -> Void)?
    private let presenter: FramePresenter
    private let timeSource: any TimeSource
    private let eventSource: (any RuntimeEventSource)?
    private let processControl: any RuntimeProcessControl
    private let escapeResolutionInterval: TimeSpan
    private let terminalProbePolicy: TerminalProbePolicy
    private var inputParser: TerminalInputParser
    private var escapeDeadline: TimeInstant?
    private var pendingDamage: DamageTracker
    private var pendingTransaction: Transaction?
    private var pendingStructureInvalidation = true
    private var isRendering = false
    private var isUpdatingFrameEnvironment = false
    private var isWaitingForEvent = false
    private let missedBudgetCounter = DiagnosticsCounter()

    /// Creates a runtime for an imperative runtime view.
    public init(
        view: any RuntimeView,
        presenter: FramePresenter,
        terminalSize: CellSize,
        motionPolicy: MotionPolicy = .standard,
        timeSource: any TimeSource = ContinuousTimeSource(),
        eventSource: (any RuntimeEventSource)? = nil,
        processControl: any RuntimeProcessControl = SystemRuntimeProcessControl(),
        inputParser: TerminalInputParser = TerminalInputParser(),
        terminalProbePolicy: TerminalProbePolicy = TerminalProbePolicy(),
        escapeResolutionInterval: TimeSpan = .milliseconds(25),
        scheduler: FrameScheduler = FrameScheduler(),
        graph: ViewGraph = ViewGraph(),
        commands: KeyboardCommandSet = KeyboardCommandSet(),
        onInput: InputHandler? = nil,
        onInputError: InputErrorHandler? = nil,
        onSignal: SignalHandler? = nil
    ) {
        precondition(escapeResolutionInterval > .zero, "The Escape-key resolution interval must be positive.")
        self.view = view
        declarativeInputDispatcher = nil
        self.presenter = presenter
        self.terminalSize = terminalSize
        self.motionPolicy = motionPolicy
        self.timeSource = timeSource
        self.eventSource = eventSource
        if let eventSource {
            invalidationChannel = RuntimeInvalidationChannel { try eventSource.wake() }
        } else {
            invalidationChannel = RuntimeInvalidationChannel()
        }
        self.processControl = processControl
        self.inputParser = inputParser
        self.terminalProbePolicy = terminalProbePolicy
        self.escapeResolutionInterval = escapeResolutionInterval
        self.scheduler = scheduler
        self.graph = graph
        self.commands = commands
        self.onInput = onInput
        self.onInputError = onInputError
        self.onSignal = onSignal
        pendingDamage = DamageTracker(bounds: CellRect(origin: .zero, size: terminalSize))
        installGraphInvalidationHandler()
    }

    /// Creates a runtime for a declarative root view.
    public init<Root: View>(
        view root: Root,
        presenter: FramePresenter,
        terminalSize: CellSize,
        motionPolicy: MotionPolicy = .standard,
        timeSource: any TimeSource = ContinuousTimeSource(),
        eventSource: (any RuntimeEventSource)? = nil,
        processControl: any RuntimeProcessControl = SystemRuntimeProcessControl(),
        inputParser: TerminalInputParser = TerminalInputParser(),
        terminalProbePolicy: TerminalProbePolicy = TerminalProbePolicy(),
        escapeResolutionInterval: TimeSpan = .milliseconds(25),
        scheduler: FrameScheduler = FrameScheduler(),
        graph: ViewGraph = ViewGraph(),
        commands: KeyboardCommandSet = KeyboardCommandSet(),
        onInput: InputHandler? = nil,
        onInputError: InputErrorHandler? = nil,
        onSignal: SignalHandler? = nil
    ) {
        precondition(escapeResolutionInterval > .zero, "The Escape-key resolution interval must be positive.")
        let declarativeView = DeclarativeRuntimeView(root: root)
        view = declarativeView
        declarativeInputDispatcher = { [weak declarativeView] event in declarativeView?.dispatch(event) }
        self.presenter = presenter
        self.terminalSize = terminalSize
        self.motionPolicy = motionPolicy
        self.timeSource = timeSource
        self.eventSource = eventSource
        if let eventSource {
            invalidationChannel = RuntimeInvalidationChannel { try eventSource.wake() }
        } else {
            invalidationChannel = RuntimeInvalidationChannel()
        }
        self.processControl = processControl
        self.inputParser = inputParser
        self.terminalProbePolicy = terminalProbePolicy
        self.escapeResolutionInterval = escapeResolutionInterval
        self.scheduler = scheduler
        self.graph = graph
        self.commands = commands
        self.onInput = onInput
        self.onInputError = onInputError
        self.onSignal = onSignal
        pendingDamage = DamageTracker(bounds: CellRect(origin: .zero, size: terminalSize))
        installGraphInvalidationHandler()
    }

    /// The next scheduled frame deadline at the current time.
    public var nextDeadline: TimeInstant? {
        scheduler.nextDeadline(at: timeSource.now)
    }

    var incrementalCounters: IncrementalRuntimeCounters? {
        (view as? any IncrementalRuntimeView)?.incrementalCounters
    }

    /// Returns the next scheduled frame deadline at a specified time.
    /// - Complexity: O(n), where n is the number of registered frame demands.
    public func nextDeadline(at instant: TimeInstant) -> TimeInstant? {
        scheduler.nextDeadline(at: instant)
    }

    /// Performs a semantic action on a declarative view node.
    /// - Returns: `true` if a node handled the action.
    /// - Complexity: O(n), where n is the number of mounted nodes and semantic nodes.
    @discardableResult
    public func performSemanticAction(_ action: SemanticAction, on id: SemanticID) -> Bool {
        guard state == .running,
            let declarativeView = view as? any DeclarativeSemanticActionRuntimeView
        else { return false }
        return declarativeView.performSemanticAction(action, on: id)
    }

    /// Starts the terminal session and requests the first frame.
    public func start() throws {
        guard state == .inactive else { throw RuntimeError.invalidState(state) }
        try presenter.startSession()
        state = .running
        invalidate(.all)
    }

    /// Stops the terminal session and event loop.
    public func stop() throws {
        guard state == .running || state == .suspended else { throw RuntimeError.invalidState(state) }
        scheduler.removeAllDemands()
        if presenter.sessionState != .inactive {
            try presenter.stopSession()
        }
        state = .stopped
        wakeEventLoop()
    }

    /// Suspends the terminal session and frame scheduling.
    public func suspend() throws {
        guard state == .running else { throw RuntimeError.invalidState(state) }
        try presenter.suspendSession()
        scheduler.removeAllDemands()
        state = .suspended
    }

    /// Resumes the terminal session and requests a complete frame.
    public func resume() throws {
        guard state == .suspended else { throw RuntimeError.invalidState(state) }
        try presenter.resumeSession()
        state = .running
        invalidate(.all)
    }

    /// Records an invalidation and requests a frame when the runtime is active.
    public func invalidate(
        _ invalidation: RuntimeInvalidation = .all,
        transaction: Transaction = Transaction.current
    ) {
        guard state == .running else { return }
        switch invalidation {
        case .all:
            pendingDamage.invalidateAll()
            if view is any IncrementalRuntimeView {
                pendingStructureInvalidation = true
            }
        case .region(let rect):
            pendingDamage.add(rect)
        }
        recordPendingTransaction(transaction)
        scheduler.requestFrame()
        wakeEventLoop()
    }

    /// Processes a high-level runtime event.
    public func process(_ event: RuntimeEvent) throws {
        switch event {
        case .invalidate(let invalidation, let transaction):
            invalidate(invalidation, transaction: transaction ?? Transaction.current)
        case .input(let event):
            guard state == .running else { return }
            let handledCommand: Bool
            if case .key(let key) = event, key.action != .release, let shortcut = key.keyboardShortcut {
                handledCommand = commands.dispatch(shortcut) != nil
            } else {
                handledCommand = false
            }
            if handledCommand == false { declarativeInputDispatcher?(event) }
            try onInput?(event)
            invalidate(.all)
        case .resize(let size):
            guard state == .running || state == .suspended else { return }
            guard size != terminalSize else { return }
            terminalSize = size
            pendingDamage = DamageTracker(bounds: CellRect(origin: .zero, size: size))
            presenter.invalidateTerminalState()
            graph.root?.invalidate(.layout)
            if state == .running {
                invalidate(.all)
            } else {
                pendingDamage.invalidateAll()
            }
        case .signal(let event):
            guard state == .running || state == .suspended else { return }
            let action = try presenter.handleSignalEvent(event)
            try onSignal?(event, action)
            switch action {
            case .terminate:
                scheduler.removeAllDemands()
                state = .stopped
            case .suspendProcess:
                scheduler.removeAllDemands()
                state = .suspended
                try processControl.suspendCurrentProcess()
            case .resumed:
                state = .running
                invalidate(.all)
            case .readSize:
                let size = try presenter.readTerminalSize()
                try process(.resize(CellSize(width: size.columns, height: size.rows)))
            }
        }
    }

    /// Processes an event from the terminal event source.
    public func process(_ event: TerminalRuntimeEvent) throws {
        switch event {
        case .inputReady:
            let output = inputParser.append(try presenter.readInput())
            try processParserOutput(output)
            escapeDeadline =
                inputParser.hasBufferedInput
                ? timeSource.now.advanced(by: escapeResolutionInterval)
                : nil
        case .inputClosed:
            guard state == .running || state == .suspended else { return }
            try stop()
        case .wake:
            drainInvalidationChannel()
        case .signal(let signal):
            try process(RuntimeEvent.signal(signal))
        }
    }

    /// Runs the event loop until the runtime stops or an error occurs.
    public func run() async throws {
        guard let eventSource else { throw RuntimeError.eventSourceUnavailable }
        if state == .inactive {
            try start()
        }
        guard state == .running || state == .suspended else {
            throw RuntimeError.invalidState(state)
        }

        do {
            try await probeSynchronizedOutput(from: eventSource)
            while state == .running || state == .suspended {
                try Task.checkCancellation()
                let instant = timeSource.now
                try resolveAmbiguousInput(at: instant)
                _ = try renderIfDue(at: instant)
                guard state == .running || state == .suspended else { break }
                if let event = try await waitForNextEvent(
                    from: eventSource,
                    timeout: nextWaitDuration(at: timeSource.now)
                ) {
                    try process(event)
                }
            }
        } catch {
            if state == .stopped { throw error }
            try cleanupAfterFailure(error)
        }
    }

    /// Renders a frame when the scheduler marks one as due.
    public func renderIfDue() throws -> RuntimeFrameResult? {
        try renderIfDue(at: timeSource.now)
    }

    /// Renders a frame at the specified time when the scheduler marks one as due.
    /// - Complexity: O(n), where n is the number of mounted nodes and rendered cells.
    public func renderIfDue(at instant: TimeInstant) throws -> RuntimeFrameResult? {
        drainInvalidationChannel()
        guard state == .running else { return nil }
        guard isRendering == false else { throw RuntimeError.reentrantFrame }
        guard let tick = scheduler.frame(at: instant) else { return nil }

        if view is any IncrementalRuntimeView {
            isUpdatingFrameEnvironment = true
            graph.setEnvironment(
                terminalSize,
                for: TerminalSizeEnvironmentKey.self,
                invalidatesDependents: true
            )
            graph.setEnvironment(
                TimelineFrameEnvironment(instant: tick.instant),
                for: TimelineFrameEnvironmentKey.self,
                invalidatesDependents: true
            )
            isUpdatingFrameEnvironment = false
        }

        if let incrementalView = view as? any IncrementalRuntimeView,
            pendingStructureInvalidation == false,
            graph.requiresStructureSampling(at: tick.instant) == false,
            graph.root != nil
        {
            return try renderIncremental(incrementalView, tick: tick)
        }

        let frameStart = timeSource.now
        isRendering = true
        let frameDamage = pendingDamage
        var transaction = pendingTransaction ?? Transaction(animationTime: instant)
        transaction.animationTime = instant
        pendingDamage.reset()
        pendingTransaction = nil
        defer { isRendering = false }

        if motionPolicy == .reduced {
            transaction.isReducedMotionEnabled = true
        }
        let context = RuntimeFrameContext(
            terminalSize: terminalSize,
            instant: tick.instant,
            deltaTime: tick.deltaTime,
            motionPolicy: motionPolicy,
            transaction: transaction
        )
        graph.setEnvironment(
            TimelineFrameEnvironment(instant: tick.instant),
            for: TimelineFrameEnvironmentKey.self,
            invalidatesDependents: false
        )
        graph.setEnvironment(
            terminalSize,
            for: TerminalSizeEnvironmentKey.self,
            invalidatesDependents: false
        )
        graph.setEnvironment(
            transaction.areAnimationsEnabled,
            for: AnimationsEnabledEnvironmentKey.self,
            invalidatesDependents: false
        )
        graph.setEnvironment(
            transaction.isReducedMotionEnabled,
            for: ReduceMotionEnvironmentKey.self,
            invalidatesDependents: false
        )

        var graphCommit: ViewGraphCommit?
        var frameCompletionActions: [MountedNodeAttributeAction] = []
        do {
            let commit = try withTransaction(transaction) {
                let plan = try graph.prepare(view.nodeDescriptor(in: context))
                return try graph.beginCommit(plan)
            }
            let reconciliationEnd = timeSource.now
            graphCommit = commit
            let sampling = graph.sampleMountedAttributesDeferringCompletions(at: tick.instant)
            frameCompletionActions.append(contentsOf: sampling.completionActions)
            try view.layout(in: context, graph: graph)
            let layoutEnd = timeSource.now
            let frame = try presenter.withRenderResources { resources in
                try view.paint(in: context, resources: &resources)
            }
            let paintEnd = timeSource.now
            guard frame.surface.size == terminalSize else {
                throw RuntimeError.invalidSurfaceSize(expected: terminalSize, actual: frame.surface.size)
            }

            let damage = combinedDamage(
                frameDamage: frameDamage,
                paintDamage: frame.damage
            )
            var presentation = try presenter.present(
                frame.surface,
                damage: damage
            )
            graph.clearDirtyFlags(includingPresentation: true)
            let commitCompletionActions = try withTransaction(transaction) {
                try graph.finishCommitDeferringCompletions(commit)
            }
            graphCommit = nil
            pendingStructureInvalidation = false
            frameCompletionActions.append(contentsOf: commitCompletionActions)
            for action in frameCompletionActions {
                action()
            }
            frameCompletionActions = []
            semantics = frame.semantics
            let activeAnimationCount = sampling.activeCount
            updateAnimationDemand(
                frame.nextFrameCadence,
                hasDeclarativeAnimations: activeAnimationCount > 0
            )
            updateTimelineDemand(sampling.frameDemand)
            let frameDuration = frameStart.duration(to: timeSource.now)
            if frameDuration > FrameScheduler.minimumFrameInterval {
                missedBudgetCounter.increment()
            }
            presentation.stats.frameDuration = frameDuration
            presentation.stats.reconciliationDuration = frameStart.duration(to: reconciliationEnd)
            presentation.stats.layoutDuration = reconciliationEnd.duration(to: layoutEnd)
            presentation.stats.paintDuration = layoutEnd.duration(to: paintEnd)
            presentation.stats.missedBudgetCount = missedBudgetCounter.value
            presentation.stats.activeAnimationCount = activeAnimationCount
            return RuntimeFrameResult(
                tick: tick,
                presentation: presentation,
                stats: presentation.stats,
                semantics: frame.semantics,
                graphRevision: graph.revision
            )
        } catch {
            let primaryError = error
            if let graphCommit {
                do {
                    try graph.rollbackCommit(graphCommit)
                } catch {
                    try cleanupAfterFailure(
                        RuntimeError.cleanupAfterFailure(
                            primaryError: String(describing: primaryError),
                            cleanupError: String(describing: error)
                        )
                    )
                }
            }
            try cleanupAfterFailure(primaryError)
        }
    }

    private func renderIncremental(
        _ incrementalView: any IncrementalRuntimeView,
        tick: FrameTick
    ) throws -> RuntimeFrameResult {
        guard isRendering == false else { throw RuntimeError.reentrantFrame }
        let frameStart = timeSource.now
        isRendering = true
        let frameDamage = pendingDamage
        pendingDamage.reset()
        defer { isRendering = false }

        var transaction = pendingTransaction ?? Transaction(animationTime: tick.instant)
        pendingTransaction = nil
        transaction.animationTime = tick.instant
        if motionPolicy == .reduced {
            transaction.isReducedMotionEnabled = true
        }
        let context = RuntimeFrameContext(
            terminalSize: terminalSize,
            instant: tick.instant,
            deltaTime: tick.deltaTime,
            motionPolicy: motionPolicy,
            transaction: transaction
        )
        graph.setEnvironment(
            transaction.areAnimationsEnabled,
            for: AnimationsEnabledEnvironmentKey.self,
            invalidatesDependents: false
        )
        graph.setEnvironment(
            transaction.isReducedMotionEnabled,
            for: ReduceMotionEnvironmentKey.self,
            invalidatesDependents: false
        )
        let activePresentationNodes = incrementalView.activePresentationNodes
        let usesSelectiveFrame =
            activePresentationNodes.isEmpty == false
            && frameDamage.isEmpty
            && pendingStructureInvalidation == false
        let graphFrame =
            try usesSelectiveFrame
            ? graph.beginFrame(nodes: activePresentationNodes)
            : graph.beginFrame()
        var completionActions: [MountedNodeAttributeAction] = []
        do {
            let sampling =
                usesSelectiveFrame == false
                ? graph.sampleMountedAttributesDeferringCompletions(at: tick.instant)
                : graph.sampleMountedAttributesDeferringCompletions(
                    at: tick.instant,
                    roots: activePresentationNodes
                )
            completionActions = sampling.completionActions
            if usesSelectiveFrame {
                try graph.captureDirtyState(for: graphFrame, nodes: activePresentationNodes)
            } else {
                try graph.captureDirtyState(for: graphFrame)
            }
            incrementalView.beginIncrementalFrame(
                in: context,
                graph: graph,
                dirtyNodes: graphFrame.dirtyNodes,
                externalDamage: frameDamage
            )
            let needsLayout = graphFrame.dirtyNodes.contains { $0.dirtyFlags.contains(.layout) }
            try incrementalView.updatePresentation(in: context, graph: graph, layout: needsLayout)
            let layoutEnd = timeSource.now
            let frame = try presenter.withRenderResources { resources in
                try incrementalView.paint(in: context, resources: &resources)
            }
            let paintEnd = timeSource.now
            guard frame.surface.size == terminalSize else {
                throw RuntimeError.invalidSurfaceSize(expected: terminalSize, actual: frame.surface.size)
            }
            var damage = frame.damage ?? DamageTracker(bounds: frame.surface.bounds)
            for dirtyNode in graphFrame.dirtyNodes where dirtyNode.localDirtyFlags.isEmpty == false {
                damage.add(dirtyNode.oldPaintBounds)
                damage.add(dirtyNode.node.paintBounds)
            }
            damage.add(contentsOf: frameDamage.rectangles)
            var presentation = try presenter.present(frame.surface, damage: damage.isEmpty ? nil : damage)
            try graph.finishFrame(graphFrame)
            incrementalView.finishIncrementalFrame()
            for action in completionActions { action() }
            semantics = frame.semantics
            updateAnimationDemand(frame.nextFrameCadence, hasDeclarativeAnimations: sampling.activeCount > 0)
            updateTimelineDemand(sampling.frameDemand)
            let frameDuration = frameStart.duration(to: timeSource.now)
            if frameDuration > FrameScheduler.minimumFrameInterval { missedBudgetCounter.increment() }
            presentation.stats.frameDuration = frameDuration
            presentation.stats.reconciliationDuration = .zero
            presentation.stats.layoutDuration = needsLayout ? frameStart.duration(to: layoutEnd) : .zero
            presentation.stats.paintDuration = layoutEnd.duration(to: paintEnd)
            presentation.stats.missedBudgetCount = missedBudgetCounter.value
            presentation.stats.activeAnimationCount = sampling.activeCount
            return RuntimeFrameResult(
                tick: tick,
                presentation: presentation,
                stats: presentation.stats,
                semantics: frame.semantics,
                graphRevision: graph.revision
            )
        } catch {
            try? graph.rollbackFrame(graphFrame)
            incrementalView.rollbackIncrementalFrame()
            pendingDamage.add(contentsOf: frameDamage.rectangles)
            scheduler.requestFrame()
            throw error
        }
    }

    private func combinedDamage(
        frameDamage: DamageTracker,
        paintDamage: DamageTracker?
    ) -> DamageTracker? {
        guard var paintDamage else {
            return frameDamage.isEmpty ? nil : frameDamage
        }
        paintDamage.add(contentsOf: frameDamage.rectangles)
        return paintDamage
    }

    private func updateAnimationDemand(
        _ cadence: TimeSpan?,
        hasDeclarativeAnimations: Bool = false
    ) {
        guard motionPolicy.allowsAnimation else {
            scheduler.remove(Self.animationDemand)
            return
        }
        guard cadence != nil || hasDeclarativeAnimations else {
            scheduler.remove(Self.animationDemand)
            return
        }
        let requestedCadence =
            hasDeclarativeAnimations
            ? cadence.map { min($0, FrameScheduler.minimumFrameInterval) } ?? FrameScheduler.minimumFrameInterval
            : cadence ?? FrameScheduler.minimumFrameInterval
        scheduler.register(Self.animationDemand, cadence: requestedCadence)
    }

    private func updateTimelineDemand(_ demand: MountedFrameDemand?) {
        guard let demand else {
            scheduler.remove(Self.timelineCadenceDemand)
            scheduler.remove(Self.timelineDeadlineDemand)
            return
        }
        if motionPolicy.allowsAnimation, let cadence = demand.cadence {
            scheduler.register(Self.timelineCadenceDemand, cadence: cadence)
        } else {
            scheduler.remove(Self.timelineCadenceDemand)
        }
        if let deadline = demand.deadline {
            scheduler.register(Self.timelineDeadlineDemand, deadline: deadline)
        } else {
            scheduler.remove(Self.timelineDeadlineDemand)
        }
    }

    private func processParserOutput(_ output: TerminalInputParserOutput) throws {
        for error in output.errors {
            onInputError?(error)
        }
        for event in output.events {
            try process(.input(event))
        }
    }

    private func probeSynchronizedOutput(from eventSource: any RuntimeEventSource) async throws {
        guard presenter.terminalCapabilities.synchronizedOutput == .unknown else { return }

        var probe = SynchronizedOutputProbe(policy: terminalProbePolicy)
        try presenter.writeCapabilityQuery(probe.start())
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: terminalProbePolicy.timeout)

        while state == .running || state == .suspended {
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else {
                try completeSynchronizedOutputTimeout()
                return
            }
            let timeout = Self.runtimeDuration(remaining)
            guard let event = try await waitForNextEvent(from: eventSource, timeout: timeout) else {
                try completeSynchronizedOutputTimeout()
                return
            }

            switch event {
            case .inputReady:
                let bytes = try presenter.readInput(
                    maximumByteCount: terminalProbePolicy.maximumResponseByteCount + 1
                )
                if let result = probe.receive(bytes) {
                    completeSynchronizedOutputProbe(result)
                    return
                }
            case .inputClosed:
                completeSynchronizedOutputProbe(.timedOut)
                try process(event)
                return
            case .wake, .signal:
                try process(event)
            }
        }
    }

    private func completeSynchronizedOutputProbe(_ result: SynchronizedOutputProbeResult) {
        presenter.applySynchronizedOutputProbeResult(result)
        if result != .supported {
            diagnostics.append(.synchronizedOutputProbe(result))
        }
    }

    private func completeSynchronizedOutputTimeout() throws {
        if terminalProbePolicy.timeoutRequirement == .mandatory {
            throw TerminalCapabilityProbeError.synchronizedOutputTimedOut(timeout: terminalProbePolicy.timeout)
        }
        completeSynchronizedOutputProbe(.timedOut)
    }

    private static func runtimeDuration(_ duration: Duration) -> TimeSpan {
        let components = duration.components
        let seconds = components.seconds * 1_000_000_000
        let nanoseconds = components.attoseconds / 1_000_000_000
        return .nanoseconds(seconds + nanoseconds)
    }

    private func resolveAmbiguousInput(at instant: TimeInstant) throws {
        guard let escapeDeadline, instant >= escapeDeadline else { return }
        self.escapeDeadline = nil
        try processParserOutput(inputParser.resolveAmbiguousEscape())
    }

    private func nextWaitDuration(at instant: TimeInstant) -> TimeSpan? {
        var deadline = state == .running ? scheduler.nextDeadline(at: instant) : nil
        if let escapeDeadline {
            deadline = deadline.map { min($0, escapeDeadline) } ?? escapeDeadline
        }
        guard let deadline else { return nil }
        return instant < deadline ? instant.duration(to: deadline) : .zero
    }

    private func waitForNextEvent(
        from eventSource: any RuntimeEventSource,
        timeout: TimeSpan?
    ) async throws -> TerminalRuntimeEvent? {
        try Task.checkCancellation()
        isWaitingForEvent = true
        defer { isWaitingForEvent = false }
        let event = try await withTaskCancellationHandler {
            try await Task.detached {
                try eventSource.nextEvent(timeout: timeout)
            }.value
        } onCancel: {
            try? eventSource.wake()
        }
        try Task.checkCancellation()
        return event
    }

    private func wakeEventLoop() {
        guard isWaitingForEvent else { return }
        try? eventSource?.wake()
    }

    private func drainInvalidationChannel() {
        if let invalidation = invalidationChannel.take() {
            invalidate(invalidation, transaction: Transaction())
        }
    }

    private func installGraphInvalidationHandler() {
        let previousContextHandler = graph.invalidationContextHandler
        graph.invalidationContextHandler = { [weak self] node, flags, context in
            previousContextHandler?(node, flags, context)
            guard let self else { return }
            if let transaction = context as? Transaction {
                self.recordPendingTransaction(transaction)
            }
            if self.view is any IncrementalRuntimeView {
                if flags.contains(.structure) {
                    self.pendingStructureInvalidation = true
                }
                guard self.isUpdatingFrameEnvironment == false else { return }
                self.scheduler.requestFrame()
                self.wakeEventLoop()
            } else {
                self.invalidate(.all)
            }
        }
    }

    private func recordPendingTransaction(_ transaction: Transaction) {
        if pendingTransaction == nil || transaction.animation != nil || transaction.completion != nil {
            pendingTransaction = transaction
        }
    }

    private func cleanupAfterFailure(_ primaryError: any Error) throws -> Never {
        scheduler.removeAllDemands()
        state = .stopped
        do {
            if presenter.sessionState != .inactive {
                try presenter.stopSession()
            }
        } catch {
            throw RuntimeError.cleanupAfterFailure(
                primaryError: String(describing: primaryError),
                cleanupError: String(describing: error)
            )
        }
        throw primaryError
    }
}
