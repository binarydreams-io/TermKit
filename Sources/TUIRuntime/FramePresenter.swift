import TUIControls
import TUIFoundation
import TUIRenderer
import TUITerminal

public protocol RuntimeTerminalSession: AnyObject {
    var capabilities: TerminalCapabilities { get }
    var state: TerminalSessionState { get }

    @discardableResult
    func start() throws -> TerminalSessionTransition

    @discardableResult
    func suspend() throws -> TerminalSessionTransition

    @discardableResult
    func resume() throws -> TerminalSessionTransition

    @discardableResult
    func stop() throws -> TerminalSessionTransition

    func present(_ bytes: [UInt8]) throws
    func writeCapabilityQuery(_ bytes: [UInt8]) throws
    func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult)
    func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction
    func readInput(maximumByteCount: Int) throws -> [UInt8]
    func readTerminalSize() throws -> TerminalSize
}

public extension RuntimeTerminalSession {
    func writeCapabilityQuery(_ bytes: [UInt8]) throws {}

    func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {}
}

extension TerminalSession: RuntimeTerminalSession {
    public func writeCapabilityQuery(_ bytes: [UInt8]) throws {
        try transport.writeAll(bytes)
    }

    public func readInput(maximumByteCount: Int) throws -> [UInt8] {
        try transport.read(maximumByteCount: maximumByteCount)
    }

    public func readTerminalSize() throws -> TerminalSize {
        try TerminalSizeReader(fileDescriptor: transport.outputFileDescriptor).read()
    }
}

public struct PresenterResult: Sendable, Hashable {
    public var didWrite: Bool
    public var stats: TUIRenderer.RenderStats

    public init(didWrite: Bool, stats: TUIRenderer.RenderStats) {
        self.didWrite = didWrite
        self.stats = stats
    }
}

@MainActor
public final class FramePresenter {
    public private(set) var frontSurface: TUIRenderer.Surface?
    public private(set) var resources: ControlRenderResources
    public private(set) var presentedFrameCount: UInt64 = 0

    public var sessionState: TerminalSessionState {
        session.state
    }

    public var terminalCapabilities: TerminalCapabilities {
        session.capabilities
    }

    private let session: any RuntimeTerminalSession
    private let differ: CellDiffer
    private let palette: SemanticPalette
    private let timeSource: any TimeSource
    private var encoder: ANSIEncoder
    private var requiresFullRepaint = true

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
            styles: StyleInterner(limits: internerLimits)
        )
        encoder = ANSIEncoder(colorMode: Self.colorMode(for: session.capabilities.color))
    }

    public func withRenderResources<Result>(
        _ body: (inout ControlRenderResources) throws -> Result
    ) rethrows -> Result {
        try body(&resources)
    }

    public func invalidateTerminalState() {
        requiresFullRepaint = true
        encoder.invalidateState()
    }

    @discardableResult
    public func startSession() throws -> TerminalSessionTransition {
        let transition = try session.start()
        invalidateTerminalState()
        return transition
    }

    @discardableResult
    public func suspendSession() throws -> TerminalSessionTransition {
        try session.suspend()
    }

    @discardableResult
    public func resumeSession() throws -> TerminalSessionTransition {
        let transition = try session.resume()
        invalidateTerminalState()
        return transition
    }

    @discardableResult
    public func stopSession() throws -> TerminalSessionTransition {
        try session.stop()
    }

    public func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
        let action = try session.handleSignalEvent(event)
        if case .resumed(requiresFullRepaint: true) = action {
            invalidateTerminalState()
        }
        return action
    }

    public func readInput(maximumByteCount: Int = 4_096) throws -> [UInt8] {
        try session.readInput(maximumByteCount: maximumByteCount)
    }

    public func writeCapabilityQuery(_ bytes: [UInt8]) throws {
        try session.writeCapabilityQuery(bytes)
    }

    public func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {
        session.applySynchronizedOutputProbeResult(result)
        invalidateTerminalState()
    }

    public func readTerminalSize() throws -> TerminalSize {
        try session.readTerminalSize()
    }

    public func present(
        _ surface: TUIRenderer.Surface,
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
        let diffStart = timeSource.now()
        let diff = try differ.diff(front: comparison, back: back, damage: fullRepaint ? nil : damage)
        let diffDuration = diffStart.duration(to: timeSource.now())
        let bytes = try encoder.encode(
            diff.operations,
            graphemes: resources.graphemes,
            styles: resources.styles,
            palette: palette,
            synchronizedOutput: false
        )

        var writeDuration = TUIDuration.zero
        if bytes.isEmpty == false {
            do {
                let writeStart = timeSource.now()
                try session.present(bytes)
                writeDuration = writeStart.duration(to: timeSource.now())
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
            stats: TUIRenderer.RenderStats(
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
        front: inout TUIRenderer.Surface?,
        back: inout TUIRenderer.Surface
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

    private func invalidatedCopy(of surface: TUIRenderer.Surface) throws -> TUIRenderer.Surface {
        var invalidated = TUIRenderer.Surface(size: surface.size)
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
                    styleID: cell.styleID,
                    displayWidth: cell.displayWidth,
                    flags: flags,
                    at: point
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
        case .ansi16, .monochrome:
            .ansi16
        }
    }
}
