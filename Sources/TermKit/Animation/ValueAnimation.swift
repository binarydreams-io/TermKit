/// Applies an animation only when a watched value changes.
public struct ValueAnimation<Value: Equatable & Sendable>: Sendable {
  /// The animation to inject after the watched value changes.
  public var animation: Animation?

  /// The most recently observed value.
  public private(set) var value: Value

  /// Creates a value-scoped animation with an initial watched value.
  public init(_ animation: Animation?, value: Value) {
    self.animation = animation
    self.value = value
  }

  /// Returns a transaction that injects the animation when the value changed.
  /// - Complexity: O(1), excluding the value's equality operation.
  public mutating func transaction(
    for newValue: Value,
    from base: Transaction = .current
  ) -> Transaction {
    guard newValue != value else { return base }
    value = newValue
    var transaction = base
    transaction.animation = transaction.areAnimationsEnabled ? animation : nil
    return transaction
  }
}
