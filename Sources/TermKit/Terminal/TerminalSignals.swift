#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A process signal that affects terminal lifecycle state.
public enum TerminalSignalEvent: Equatable, Sendable {
  /// An interrupt signal.
  case interrupt
  /// A termination signal.
  case terminate
  /// A quit signal.
  case quit
  /// A hangup signal.
  case hangup
  /// A terminal-stop signal.
  case suspend
  /// A continue signal.
  case resume
  /// A terminal-size change signal.
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
  /// Stop the runtime.
  case terminate
  /// Suspend the current process.
  case suspendProcess
  /// Continue and indicate whether the caller must repaint.
  case resumed(requiresFullRepaint: Bool)
  /// Read the current terminal size.
  case readSize
}

extension TerminalSession {
  /// Applies a signal event outside the signal handler.
  ///
  /// A suspend action means that the caller can now stop the process safely.
  public func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
    switch event {
    case .interrupt, .terminate, .quit, .hangup:
      if state != .inactive {
        try stop()
      }
      return .terminate
    case .suspend:
      if state == .active {
        try suspend()
      }
      return .suspendProcess
    case .resume:
      if state == .suspended {
        try resume()
      }
      return .resumed(requiresFullRepaint: true)
    case .windowChanged:
      return .readSize
    }
  }
}
