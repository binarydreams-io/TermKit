#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A terminal session lifecycle state.
public enum TerminalSessionState: Equatable, Sendable {
    case inactive
    case active
    case suspended
}

/// A completed terminal session transition.
public enum TerminalSessionTransition: Equatable, Sendable {
    case started
    case suspended
    case resumed(requiresFullRepaint: Bool)
    case stopped
}

/// A terminal session failure.
public enum TerminalSessionError: Error, Equatable, Sendable {
    case notTerminal(fileDescriptor: Int32)
    case posix(operation: TerminalPOSIXOperation, errorCode: Int32)
    case transport(TerminalTransportError)
    case invalidTransition(from: TerminalSessionState, operation: String)
    indirect case cleanupAfterFailure(primaryError: String, cleanupError: TerminalSessionError)
}

/// Terminal modes that a session owns.
public struct TerminalSessionConfiguration: Equatable, Sendable {
    public var usesAlternateScreen: Bool
    public var hidesCursor: Bool
    public var enablesBracketedPaste: Bool
    public var enablesSGRMouse: Bool
    public var enablesFocusReporting: Bool
    public var enablesKittyKeyboard: Bool

    /// Creates a terminal session configuration.
    public init(
        usesAlternateScreen: Bool = true,
        hidesCursor: Bool = true,
        enablesBracketedPaste: Bool = true,
        enablesSGRMouse: Bool = true,
        enablesFocusReporting: Bool = true,
        enablesKittyKeyboard: Bool = false
    ) {
        self.usesAlternateScreen = usesAlternateScreen
        self.hidesCursor = hidesCursor
        self.enablesBracketedPaste = enablesBracketedPaste
        self.enablesSGRMouse = enablesSGRMouse
        self.enablesFocusReporting = enablesFocusReporting
        self.enablesKittyKeyboard = enablesKittyKeyboard
    }
}

/// Owns termios and terminal protocol modes for one terminal session.
///
/// Use this type from one runtime executor. Signal handlers must not call it.
/// Signal handlers can write a signal number to a self-pipe for later delivery.
public final class TerminalSession {
    public let transport: TerminalTransport
    public let configuration: TerminalSessionConfiguration
    public private(set) var capabilities: TerminalCapabilities
    public private(set) var state: TerminalSessionState = .inactive

    private var originalAttributes: termios?

    /// Creates an inactive terminal session without terminal I/O.
    public init(
        transport: TerminalTransport = TerminalTransport(),
        capabilities: TerminalCapabilities = TerminalCapabilities(),
        configuration: TerminalSessionConfiguration = TerminalSessionConfiguration()
    ) {
        self.transport = transport
        self.capabilities = capabilities
        self.configuration = configuration
    }

    deinit {
        try? restoreForExit()
    }

    /// Starts raw mode and enables configured terminal modes.
    @discardableResult
    public func start() throws -> TerminalSessionTransition {
        guard state == .inactive else {
            throw TerminalSessionError.invalidTransition(from: state, operation: "start")
        }
        try activate(capturingOriginalAttributes: true)
        state = .active
        return .started
    }

    /// Suspends the session after restoring shell-compatible terminal state.
    @discardableResult
    public func suspend() throws -> TerminalSessionTransition {
        guard state == .active else {
            throw TerminalSessionError.invalidTransition(from: state, operation: "suspend")
        }
        try restoreTerminalModes()
        state = .suspended
        return .suspended
    }

    /// Resumes raw mode and requests a full repaint.
    @discardableResult
    public func resume() throws -> TerminalSessionTransition {
        guard state == .suspended else {
            throw TerminalSessionError.invalidTransition(from: state, operation: "resume")
        }
        try activate(capturingOriginalAttributes: true)
        state = .active
        return .resumed(requiresFullRepaint: true)
    }

    /// Stops the session and restores terminal state.
    @discardableResult
    public func stop() throws -> TerminalSessionTransition {
        guard state != .inactive else {
            throw TerminalSessionError.invalidTransition(from: state, operation: "stop")
        }
        try restoreForExit()
        return .stopped
    }

    /// Updates the synchronized-output state from a completed probe.
    public func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {
        capabilities = SynchronizedOutputProbe.applying(result, to: capabilities)
    }

    /// Writes a complete frame and uses synchronized output when supported.
    public func present(_ bytes: [UInt8]) throws {
        guard state == .active else {
            throw TerminalSessionError.invalidTransition(from: state, operation: "present")
        }
        do {
            try transport.withFrame(synchronized: capabilities.synchronizedOutput == .supported) {
                try transport.appendToFrame(bytes)
            }
        } catch let error as TerminalTransportError {
            do {
                try restoreForExit()
            } catch let cleanupError as TerminalSessionError {
                throw TerminalSessionError.cleanupAfterFailure(
                    primaryError: String(describing: error),
                    cleanupError: cleanupError
                )
            }
            throw TerminalSessionError.transport(error)
        }
    }

    /// Runs synchronous work and restores the session on every exit path.
    public func withActiveSession<Result>(_ operation: (TerminalSession) throws -> Result) throws -> Result {
        try start()
        do {
            let result = try operation(self)
            try stop()
            return result
        } catch {
            let primaryError = error
            do {
                if state != .inactive { try restoreForExit() }
            } catch let cleanupError as TerminalSessionError {
                throw TerminalSessionError.cleanupAfterFailure(
                    primaryError: String(describing: primaryError),
                    cleanupError: cleanupError
                )
            }
            throw primaryError
        }
    }

    /// Runs asynchronous work and restores the session after cancellation or failure.
    public func withActiveSession<Result>(_ operation: (TerminalSession) async throws -> Result) async throws -> Result {
        try start()
        do {
            let result = try await operation(self)
            try Task.checkCancellation()
            try stop()
            return result
        } catch {
            let primaryError = error
            do {
                if state != .inactive { try restoreForExit() }
            } catch let cleanupError as TerminalSessionError {
                throw TerminalSessionError.cleanupAfterFailure(
                    primaryError: String(describing: primaryError),
                    cleanupError: cleanupError
                )
            }
            throw primaryError
        }
    }
}

extension TerminalSession {
    private func activate(capturingOriginalAttributes: Bool) throws {
        let calls = transport.systemCalls
        guard calls.isTerminal(transport.inputFileDescriptor) == 1 else {
            throw TerminalSessionError.notTerminal(fileDescriptor: transport.inputFileDescriptor)
        }

        var attributes = termios()
        guard calls.getAttributes(transport.inputFileDescriptor, &attributes) == 0 else {
            throw TerminalSessionError.posix(operation: .getAttributes, errorCode: calls.errorCode())
        }
        if capturingOriginalAttributes {
            originalAttributes = attributes
        }

        makeRaw(&attributes)
        guard calls.setAttributes(transport.inputFileDescriptor, TCSAFLUSH, &attributes) == 0 else {
            throw TerminalSessionError.posix(operation: .setAttributes, errorCode: calls.errorCode())
        }

        do {
            try transport.writeAll(activationBytes())
        } catch let error as TerminalTransportError {
            try? restoreAttributes()
            throw TerminalSessionError.transport(error)
        }
    }

    private func restoreForExit() throws {
        guard state != .inactive else { return }
        try restoreTerminalModes()
        state = .inactive
        originalAttributes = nil
    }

    private func restoreTerminalModes() throws {
        var firstError: TerminalSessionError?
        do {
            try transport.writeAll(deactivationBytes())
        } catch let error as TerminalTransportError {
            firstError = .transport(error)
        }
        do {
            try restoreAttributes()
        } catch let error as TerminalSessionError where firstError == nil {
            firstError = error
        }
        if let firstError { throw firstError }
    }

    private func restoreAttributes() throws {
        guard var originalAttributes else { return }
        let calls = transport.systemCalls
        guard calls.setAttributes(transport.inputFileDescriptor, TCSAFLUSH, &originalAttributes) == 0 else {
            throw TerminalSessionError.posix(operation: .setAttributes, errorCode: calls.errorCode())
        }
    }

    private func makeRaw(_ attributes: inout termios) {
        attributes.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        attributes.c_oflag &= ~tcflag_t(OPOST)
        attributes.c_cflag |= tcflag_t(CS8)
        attributes.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        withUnsafeMutablePointer(to: &attributes.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { controlCharacters in
                controlCharacters[Int(VMIN)] = 0
                controlCharacters[Int(VTIME)] = 0
            }
        }
    }

    private func activationBytes() -> [UInt8] {
        var output = ""
        if configuration.usesAlternateScreen { output += "\u{1B}[?1049h" }
        if configuration.hidesCursor { output += "\u{1B}[?25l" }
        if configuration.enablesBracketedPaste, capabilities.supportsBracketedPaste {
            output += "\u{1B}[?2004h"
        }
        if configuration.enablesSGRMouse, capabilities.supportsSGRMouse {
            output += "\u{1B}[?1000h\u{1B}[?1006h"
        }
        if configuration.enablesFocusReporting, capabilities.supportsFocusReporting {
            output += "\u{1B}[?1004h"
        }
        if configuration.enablesKittyKeyboard, capabilities.supportsKittyKeyboard {
            output += "\u{1B}[>1u"
        }
        return Array(output.utf8)
    }

    private func deactivationBytes() -> [UInt8] {
        var output = ""
        if configuration.enablesKittyKeyboard, capabilities.supportsKittyKeyboard {
            output += "\u{1B}[<u"
        }
        output += "\u{1B}[?1004l"
        output += "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
        output += "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
        output += "\u{1B}[?2004l"
        if configuration.hidesCursor { output += "\u{1B}[?25h" }
        output += "\u{1B}[0m"
        if configuration.usesAlternateScreen { output += "\u{1B}[?1049l" }
        return Array(output.utf8)
    }
}
