import Dispatch
import Foundation
import Testing
import TUIFoundation
import TUIRenderer
import TUITerminal

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import TUIRuntime

@MainActor
struct FramePresenterTests {
    @Test("An unchanged frame does not write")
    func unchangedFrameDoesNotWrite() throws {
        let session = FakeTerminalSession()
        let timeSource = SteppedTimeSource(step: .nanoseconds(3))
        let presenter = FramePresenter(session: session, timeSource: timeSource)
        _ = try session.start()
        let surface = try makeSurface("abc", resources: presenter)

        let first = try presenter.present(surface)
        let second = try presenter.present(surface)

        #expect(first.didWrite)
        #expect(first.stats.wasFullRepaint)
        #expect(first.stats.diffDuration == .nanoseconds(3))
        #expect(first.stats.writeDuration == .nanoseconds(3))
        #expect(first.stats.encodedByteCount > 0)
        #expect(first.stats.damagedCellCount == 3)
        #expect(first.stats.scannedCellCount == 3)
        #expect(first.stats.changedCellCount == 3)
        #expect(first.stats.internerByteCount > 0)
        #expect(second.didWrite == false)
        #expect(second.stats.diffDuration == .nanoseconds(3))
        #expect(second.stats.writeDuration == .zero)
        #expect(second.stats.encodedByteCount == 0)
        #expect(second.stats.damagedCellCount == 3)
        #expect(second.stats.scannedCellCount == 3)
        #expect(second.stats.changedCellCount == 0)
        #expect(session.presentationCount == 1)
    }

    @Test("A frame is one logical session write")
    func oneLogicalWritePerFrame() throws {
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session)
        _ = try session.start()

        _ = try presenter.present(makeSurface("abc", resources: presenter))
        _ = try presenter.present(makeSurface("axc", resources: presenter))

        #expect(session.presentationCount == 2)
        #expect(session.presentedPayloads.allSatisfy { $0.isEmpty == false })
    }

    @Test("Damage limits diff scanning and output to one cell")
    func damagedCellUsesLocalDiff() throws {
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session)
        _ = try session.start()
        _ = try presenter.present(makeSurface("abc", resources: presenter))
        var damage = DamageTracker(bounds: CellRect(x: 0, y: 0, width: 3, height: 1))
        damage.add(CellRect(x: 1, y: 0, width: 1, height: 1))

        let result = try presenter.present(
            makeSurface("axc", resources: presenter),
            damage: damage
        )

        #expect(result.stats.scannedCellCount == 1)
        #expect(result.stats.damagedCellCount == 1)
        #expect(result.stats.changedCellCount == 1)
        #expect(String(decoding: session.presentedPayloads.last ?? [], as: UTF8.self).hasSuffix("x"))
    }

    @Test("Damage counts requested cells even when they are unchanged")
    func unchangedDamagedCellIsCounted() throws {
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session)
        _ = try session.start()
        let surface = try makeSurface("abc", resources: presenter)
        _ = try presenter.present(surface)
        var damage = DamageTracker(bounds: surface.bounds)
        damage.add(CellRect(x: 1, y: 0, width: 1, height: 1))

        let result = try presenter.present(surface, damage: damage)

        #expect(result.didWrite == false)
        #expect(result.stats.damagedCellCount == 1)
        #expect(result.stats.scannedCellCount == 1)
        #expect(result.stats.changedCellCount == 0)
    }

    @Test("Damage remains distinct from forced repaint scanner work")
    func damageScannerAndChangeCountsDiffer() throws {
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session)
        _ = try session.start()
        _ = try presenter.present(makeSurface("abcd", resources: presenter))
        var damage = DamageTracker(bounds: CellRect(x: 0, y: 0, width: 4, height: 1))
        damage.add(CellRect(x: 0, y: 0, width: 1, height: 1))

        let result = try presenter.present(
            makeSurface("axyd", resources: presenter),
            damage: damage,
            forceFullRepaint: true
        )

        #expect(result.stats.damagedCellCount == 1)
        #expect(result.stats.scannedCellCount == 4)
        #expect(result.stats.changedCellCount == 4)
    }

    @Test("Synchronized framing is delegated to the terminal session")
    func synchronizedFallbackFraming() throws {
        let fallback = FakeTerminalSession(synchronizedOutput: .unsupported)
        let synchronized = FakeTerminalSession(synchronizedOutput: .supported)
        let fallbackPresenter = FramePresenter(session: fallback)
        let synchronizedPresenter = FramePresenter(session: synchronized)
        _ = try fallback.start()
        _ = try synchronized.start()

        _ = try fallbackPresenter.present(makeSurface("a", resources: fallbackPresenter))
        _ = try synchronizedPresenter.present(makeSurface("a", resources: synchronizedPresenter))

        let begin = TerminalTransport.beginSynchronizedOutput
        let end = TerminalTransport.endSynchronizedOutput
        #expect(fallback.physicalWrites[0].starts(with: begin) == false)
        #expect(synchronized.physicalWrites[0].starts(with: begin))
        #expect(synchronized.physicalWrites[0].suffix(end.count).elementsEqual(end))
        #expect(synchronized.presentedPayloads[0].starts(with: begin) == false)
    }

    @Test("Real terminal session presents one synchronized physical write")
    func terminalSessionIntegration() throws {
        let script = RuntimeTerminalPOSIXScript()
        let session = TerminalSession(
            transport: TerminalTransport(systemCalls: script.calls),
            capabilities: TerminalCapabilities(color: .trueColor, synchronizedOutput: .supported),
            configuration: TerminalSessionConfiguration(
                usesAlternateScreen: false,
                hidesCursor: false,
                enablesBracketedPaste: false,
                enablesSGRMouse: false,
                enablesFocusReporting: false
            )
        )
        let presenter = FramePresenter(session: session)
        _ = try presenter.startSession()

        _ = try presenter.present(makeSurface("a", resources: presenter))

        let writes = script.capturedWrites
        #expect(writes.count == 1)
        #expect(writes[0].starts(with: TerminalTransport.beginSynchronizedOutput))
        #expect(writes[0].suffix(TerminalTransport.endSynchronizedOutput.count).elementsEqual(
            TerminalTransport.endSynchronizedOutput
        ))
        _ = try presenter.stopSession()
    }

    @Test("Interner rebuild retains live cells and forces repaint")
    func internerRebuild() throws {
        let limits = InternerLimits(
            rebuildEntryCount: 4,
            maximumEntryCount: 8,
            rebuildByteCount: 1_024,
            maximumByteCount: 2_048
        )
        let session = FakeTerminalSession()
        let presenter = FramePresenter(session: session, internerLimits: limits)
        _ = try session.start()
        let surface = try makeSurface("x", resources: presenter)
        _ = try presenter.present(surface)
        _ = try presenter.withRenderResources { resources in
            _ = try resources.graphemes.intern("y")
            _ = try resources.graphemes.intern("z")
        }

        let result = try presenter.present(surface)

        #expect(result.stats.rebuiltInterners)
        #expect(result.stats.wasFullRepaint)
        #expect(presenter.resources.graphemes.stats.entryCount == 2)
        #expect(session.presentationCount == 2)
    }

    private func makeSurface(_ text: String, resources presenter: FramePresenter) throws -> TUIRenderer.Surface {
        var surface = TUIRenderer.Surface(size: CellSize(width: text.count, height: 1))
        try presenter.withRenderResources { resources in
            for (index, character) in text.enumerated() {
                let identifier = try resources.graphemes.intern(character)
                _ = try surface.write(graphemeID: identifier, at: CellPoint(x: index, y: 0))
            }
        }
        return surface
    }
}

final class SteppedTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let step: TUIDuration
    private var current = TimeInstant.zero

    init(step: TUIDuration) {
        self.step = step
    }

    func now() -> TimeInstant {
        lock.withLock {
            defer { current = current.advanced(by: step) }
            return current
        }
    }
}

private final class RuntimeTerminalPOSIXScript: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TUIRuntimeTests.terminal-posix")
    private var writes: [[UInt8]] = []

    var capturedWrites: [[UInt8]] {
        queue.sync { writes }
    }

    var calls: TerminalPOSIXCalls {
        TerminalPOSIXCalls(
            read: { _, _, _ in 0 },
            write: { [self] _, pointer, count in
                let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: count))
                queue.sync { writes.append(bytes) }
                return count
            },
            getAttributes: { _, attributes in
                attributes.pointee = termios()
                return 0
            },
            setAttributes: { _, _, _ in 0 },
            isTerminal: { _ in 1 },
            errorCode: { 0 }
        )
    }
}

final class FakeTerminalSession: RuntimeTerminalSession {
    enum PresentationError: Error {
        case expected
    }

    private(set) var state: TerminalSessionState = .inactive
    private(set) var presentedPayloads: [[UInt8]] = []
    private(set) var physicalWrites: [[UInt8]] = []
    private(set) var events: [TerminalSignalEvent] = []
    private(set) var stopCount = 0
    var capabilities: TerminalCapabilities
    var inputBytes: [UInt8] = []
    var terminalSize = TerminalSize(columns: 1, rows: 1)
    var presentationError: PresentationError?

    var presentationCount: Int {
        presentedPayloads.count
    }

    init(synchronizedOutput: TerminalCapabilitySupport = .unsupported) {
        capabilities = TerminalCapabilities(color: .trueColor, synchronizedOutput: synchronizedOutput)
    }

    func start() throws -> TerminalSessionTransition {
        state = .active
        return .started
    }

    func suspend() throws -> TerminalSessionTransition {
        state = .suspended
        return .suspended
    }

    func resume() throws -> TerminalSessionTransition {
        state = .active
        return .resumed(requiresFullRepaint: true)
    }

    func stop() throws -> TerminalSessionTransition {
        stopCount += 1
        state = .inactive
        return .stopped
    }

    func present(_ bytes: [UInt8]) throws {
        if let presentationError {
            throw presentationError
        }
        presentedPayloads.append(bytes)
        if capabilities.synchronizedOutput == .supported {
            physicalWrites.append(TerminalTransport.beginSynchronizedOutput + bytes + TerminalTransport.endSynchronizedOutput)
        } else {
            physicalWrites.append(bytes)
        }
    }

    func writeCapabilityQuery(_ bytes: [UInt8]) throws {
        physicalWrites.append(bytes)
    }

    func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {
        capabilities = SynchronizedOutputProbe.applying(result, to: capabilities)
    }

    func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
        events.append(event)
        switch event {
        case .interrupt, .terminate, .quit, .hangup:
            state = .inactive
            return .terminate
        case .suspend:
            state = .suspended
            return .suspendProcess
        case .resume:
            state = .active
            return .resumed(requiresFullRepaint: true)
        case .windowChanged:
            return .readSize
        }
    }

    func readInput(maximumByteCount: Int) throws -> [UInt8] {
        let count = min(maximumByteCount, inputBytes.count)
        defer { inputBytes.removeFirst(count) }
        return Array(inputBytes.prefix(count))
    }

    func readTerminalSize() throws -> TerminalSize {
        terminalSize
    }
}
