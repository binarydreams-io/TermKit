import Foundation

/// Provides exclusive access to mutable `Sendable` state.
public final class LockedState<State: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(_ initialState: State) {
        state = initialState
    }

    public func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
