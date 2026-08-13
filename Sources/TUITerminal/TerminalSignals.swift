#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A process signal that affects terminal lifecycle state.
public enum TerminalSignalEvent: Equatable, Sendable {
    case interrupt
    case terminate
    case quit
    case hangup
    case suspend
    case resume
    case windowChanged

    /// Creates an event from a platform signal number.
    public init?(signalNumber: Int32) {
        switch signalNumber {
        case SIGINT: self = .interrupt
        case SIGTERM: self = .terminate
        case SIGQUIT: self = .quit
        case SIGHUP: self = .hangup
        case SIGTSTP: self = .suspend
        case SIGCONT: self = .resume
        case SIGWINCH: self = .windowChanged
        default: return nil
        }
    }
}

/// The runtime action required after a signal event.
public enum TerminalSignalAction: Equatable, Sendable {
    case terminate
    case suspendProcess
    case resumed(requiresFullRepaint: Bool)
    case readSize
}

extension TerminalSession {
    /// Applies a signal event outside the signal handler.
    ///
    /// A suspend action means that the caller can now stop the process safely.
    public func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
        switch event {
        case .interrupt, .terminate, .quit, .hangup:
            if state != .inactive { try stop() }
            return .terminate
        case .suspend:
            if state == .active { try suspend() }
            return .suspendProcess
        case .resume:
            if state == .suspended { try resume() }
            return .resumed(requiresFullRepaint: true)
        case .windowChanged:
            return .readSize
        }
    }
}
