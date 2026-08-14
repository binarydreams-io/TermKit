import Foundation

/// Provides exclusive access to mutable `Sendable` state.
public final class LockedState<State: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var state: State

  /// Creates locked state with an initial value.
  public init(_ initialState: State) {
    self.state = initialState
  }

  /// Runs a closure while holding exclusive access to the state.
  public func withLock<Result>(_ body: (_ state: inout State) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&state)
  }
}
