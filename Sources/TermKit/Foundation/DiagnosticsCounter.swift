/// A thread-safe counter for diagnostics and instrumentation.
public final class DiagnosticsCounter: Sendable {
  private let count = LockedState(0)

  /// Creates a counter with a value of zero.
  public init() {}

  /// The current counter value.
  public var value: Int {
    count.withLock { $0 }
  }

  /// Increases the counter and returns its new value.
  @discardableResult
  public func increment(by amount: Int = 1) -> Int {
    precondition(amount >= 0, "A diagnostics counter increment cannot be negative.")
    return count.withLock { value in
      let (result, overflow) = value.addingReportingOverflow(amount)
      precondition(overflow == false, "A diagnostics counter cannot exceed Int.max.")
      value = result
      return result
    }
  }

  /// Resets the counter and returns its previous value.
  @discardableResult
  public func reset() -> Int {
    count.withLock { value in
      let previous = value
      value = 0
      return previous
    }
  }
}
