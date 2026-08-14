/// Defines the terminal session operations required by the runtime.
public protocol RuntimeTerminalSession: AnyObject {
    /// The capabilities detected for the terminal.
    var capabilities: TerminalCapabilities { get }
    /// The current terminal session state.
    var state: TerminalSessionState { get }

    /// Starts the terminal session.
    @discardableResult
    func start() throws -> TerminalSessionTransition

    /// Suspends the terminal session.
    @discardableResult
    func suspend() throws -> TerminalSessionTransition

    /// Resumes the terminal session.
    @discardableResult
    func resume() throws -> TerminalSessionTransition

    /// Stops the terminal session.
    @discardableResult
    func stop() throws -> TerminalSessionTransition

    /// Writes encoded frame bytes to the terminal.
    func present(_ bytes: [UInt8]) throws
    /// Writes a terminal capability query.
    func writeCapabilityQuery(_ bytes: [UInt8]) throws
    /// Applies the result of a synchronized-output probe.
    func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult)
    /// Handles a terminal signal and returns the required runtime action.
    func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction
    /// Reads up to the specified number of input bytes.
    func readInput(maximumByteCount: Int) throws -> [UInt8]
    /// Reads the current terminal size.
    func readTerminalSize() throws -> TerminalSize
}

extension RuntimeTerminalSession {
    /// Ignores a capability query by default.
    public func writeCapabilityQuery(_ bytes: [UInt8]) throws {}

    /// Ignores a synchronized-output probe result by default.
    public func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {}
}

extension TerminalSession: RuntimeTerminalSession {
    /// Writes a capability query through the session transport.
    public func writeCapabilityQuery(_ bytes: [UInt8]) throws {
        try transport.writeAll(bytes)
    }

    /// Reads input bytes from the session transport.
    public func readInput(maximumByteCount: Int) throws -> [UInt8] {
        try transport.read(maximumByteCount: maximumByteCount)
    }

    /// Reads the terminal size from the session output descriptor.
    public func readTerminalSize() throws -> TerminalSize {
        try TerminalSizeReader(fileDescriptor: transport.outputFileDescriptor).read()
    }
}

/// Reports the result of presenting one frame.
public struct PresenterResult: Sendable, Hashable {
    /// A Boolean value that indicates whether the presenter wrote bytes.
    public var didWrite: Bool
    /// The rendering statistics for the frame.
    public var stats: RenderStats

    /// Creates a presentation result.
    public init(didWrite: Bool, stats: RenderStats) {
        self.didWrite = didWrite
        self.stats = stats
    }
}

/// Converts rendered surfaces into terminal output and tracks presentation state.
@MainActor
public final class FramePresenter {
    /// The last surface accepted by the presenter.
    public private(set) var frontSurface: Surface?
    /// The interned resources used to render controls.
    public private(set) var resources: ControlRenderResources
    /// The number of frames accepted by the presenter.
    public private(set) var presentedFrameCount: UInt64 = 0

    /// The current terminal session state.
    public var sessionState: TerminalSessionState {
        session.state
    }

    /// The capabilities detected for the terminal.
    public var terminalCapabilities: TerminalCapabilities {
        session.capabilities
    }

    private let session: any RuntimeTerminalSession
    private let differ: CellDiffer
    private let palette: SemanticPalette
    private let timeSource: any TimeSource
    private var encoder: ANSIEncoder
    private var requiresFullRepaint = true

    /// Creates a frame presenter for a terminal session.
    public init(
        session: any RuntimeTerminalSession,
        internerLimits: InternerLimits = InternerLimits(),
        differ: CellDiffer = CellDiffer(),
        palette: SemanticPalette = SemanticPalette(),
        timeSource: any TimeSource = ContinuousTimeSource()
    ) {
        self.session = session
        self.differ = differ
        self.palette = palette
        self.timeSource = timeSource
        resources = ControlRenderResources(
            graphemes: GraphemeInterner(limits: internerLimits),
            styles: StyleInterner(limits: internerLimits),
            colorCapability: session.capabilities.color
        )
        encoder = ANSIEncoder(colorMode: Self.colorMode(for: session.capabilities.color))
    }

    /// Provides mutable render resources to a closure.
    public func withRenderResources<Result>(
        _ body: (_ resources: inout ControlRenderResources) throws -> Result
    ) rethrows -> Result {
        try body(&resources)
    }

    /// Requires the next presentation to repaint the complete surface.
    public func invalidateTerminalState() {
        requiresFullRepaint = true
        encoder.invalidateState()
    }

    /// Starts the terminal session and invalidates cached terminal state.
    @discardableResult
    public func startSession() throws -> TerminalSessionTransition {
        let transition = try session.start()
        invalidateTerminalState()
        return transition
    }

    /// Suspends the terminal session.
    @discardableResult
    public func suspendSession() throws -> TerminalSessionTransition {
        try session.suspend()
    }

    /// Resumes the terminal session and invalidates cached terminal state.
    @discardableResult
    public func resumeSession() throws -> TerminalSessionTransition {
        let transition = try session.resume()
        invalidateTerminalState()
        return transition
    }

    /// Stops the terminal session.
    @discardableResult
    public func stopSession() throws -> TerminalSessionTransition {
        try session.stop()
    }

    /// Handles a terminal signal and updates cached state when required.
    public func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
        let action = try session.handleSignalEvent(event)
        if case .resumed(requiresFullRepaint: true) = action {
            invalidateTerminalState()
        }
        return action
    }

    /// Reads up to the specified number of terminal input bytes.
    public func readInput(maximumByteCount: Int = 4_096) throws -> [UInt8] {
        try session.readInput(maximumByteCount: maximumByteCount)
    }

    /// Writes a terminal capability query.
    public func writeCapabilityQuery(_ bytes: [UInt8]) throws {
        try session.writeCapabilityQuery(bytes)
    }

    /// Applies a synchronized-output probe result and invalidates cached state.
    public func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {
        session.applySynchronizedOutputProbeResult(result)
        invalidateTerminalState()
    }

    /// Reads the current terminal size.
    public func readTerminalSize() throws -> TerminalSize {
        try session.readTerminalSize()
    }

    /// Presents a rendered surface to the terminal.
    /// - Complexity: O(n), where n is the number of cells scanned or remapped.
    public func present(
        _ surface: Surface,
        damage: DamageTracker? = nil,
        forceFullRepaint: Bool = false
    ) throws -> PresenterResult {
        var back = surface
        try back.validateWideCells()
        var front = frontSurface
        let rebuiltInterners = try rebuildInternersIfNeeded(front: &front, back: &back)
        let isSizeChange = front?.size != back.size
        let fullRepaint = forceFullRepaint || requiresFullRepaint || isSizeChange || rebuiltInterners
        let comparison = try fullRepaint ? invalidatedCopy(of: back) : front ?? invalidatedCopy(of: back)

        if fullRepaint {
            encoder.invalidateState()
        }
        let diffStart = timeSource.now
        let diff = try differ.diff(front: comparison, back: back, damage: fullRepaint ? nil : damage)
        let diffDuration = diffStart.duration(to: timeSource.now)
        let bytes = try encoder.encode(
            diff.operations,
            graphemes: resources.graphemes,
            styles: resources.styles,
            palette: palette,
            synchronizedOutput: false
        )

        var writeDuration = TimeSpan.zero
        if bytes.isEmpty == false {
            do {
                let writeStart = timeSource.now
                try session.present(bytes)
                writeDuration = writeStart.duration(to: timeSource.now)
            } catch {
                invalidateTerminalState()
                throw error
            }
        }

        frontSurface = back
        requiresFullRepaint = false
        presentedFrameCount &+= 1
        return PresenterResult(
            didWrite: bytes.isEmpty == false,
            stats: RenderStats(
                diffDuration: diffDuration,
                writeDuration: writeDuration,
                encodedByteCount: bytes.count,
                damagedCellCount: damage?.damagedCellCount ?? back.bounds.cellCount,
                internerByteCount: resources.graphemes.stats.estimatedByteCount
                    + resources.styles.stats.estimatedByteCount,
                scannedCellCount: diff.scannedCellCount,
                changedCellCount: diff.changedCellCount,
                operationCount: diff.operations.count,
                wasFullRepaint: fullRepaint,
                rebuiltInterners: rebuiltInterners
            )
        )
    }

    private func rebuildInternersIfNeeded(
        front: inout Surface?,
        back: inout Surface
    ) throws -> Bool {
        let rebuildGraphemes = resources.graphemes.stats.requiresRebuild
        let rebuildStyles = resources.styles.stats.requiresRebuild
        guard rebuildGraphemes || rebuildStyles else { return false }

        var rebuiltResources = resources
        let surfaces = [front, back].compactMap { $0 }
        if rebuildGraphemes {
            let remap = try rebuiltResources.graphemes.rebuild(
                retaining: surfaces.lazy.flatMap { $0.cells.lazy.map(\.graphemeID) }
            )
            if front != nil {
                try front?.remapGraphemes(using: remap)
            }
            try back.remapGraphemes(using: remap)
        }
        if rebuildStyles {
            let remap = try rebuiltResources.styles.rebuild(
                retaining: surfaces.lazy.flatMap { $0.cells.lazy.map(\.styleID) }
            )
            if front != nil {
                try front?.remapStyles(using: remap)
            }
            try back.remapStyles(using: remap)
        }
        resources = rebuiltResources
        frontSurface = front
        encoder.invalidateState()
        return true
    }

    private func invalidatedCopy(of surface: Surface) throws -> Surface {
        var invalidated = Surface(size: surface.size)
        for y in 0..<surface.size.height {
            var x = 0
            while x < surface.size.width {
                let point = CellPoint(x: x, y: y)
                let cell = surface[point]
                if cell.isContinuation {
                    x += 1
                    continue
                }
                var flags = cell.flags
                flags.formSymmetricDifference(.explicitBlank)
                _ = try invalidated.write(
                    graphemeID: cell.graphemeID,
                    at: point,
                    styleID: cell.styleID,
                    displayWidth: cell.displayWidth,
                    flags: flags
                )
                x += Int(cell.displayWidth)
            }
        }
        return invalidated
    }

    private static func colorMode(for capability: TerminalColorCapability) -> ANSIColorMode {
        switch capability {
        case .trueColor:
            .trueColor
        case .ansi256:
            .indexed256
        case .ansi16:
            .ansi16
        case .monochrome:
            .monochrome
        }
    }
}
