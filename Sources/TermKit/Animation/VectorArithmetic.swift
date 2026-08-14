/// A vector that supports interpolation through arithmetic operations.
public protocol VectorArithmetic: AdditiveArithmetic, Sendable {
  /// Multiplies each component by a scalar.
  /// - Complexity: O(1) for fixed-size vectors.
  mutating func scale(by scalar: Double)
  /// The sum of the squared component magnitudes.
  var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
  /// Returns a copy multiplied by a scalar.
  /// - Complexity: The same as ``scale(by:)``.
  public func scaled(by scalar: Double) -> Self {
    var result = self
    result.scale(by: scalar)
    return result
  }

  /// Interpolates linearly between two vectors.
  /// - Complexity: O(1) for fixed-size vectors.
  public static func interpolated(from start: Self, to end: Self, progress: Double) -> Self {
    start + (end - start).scaled(by: progress)
  }
}

extension Double: VectorArithmetic {
  /// Multiplies this value by a scalar.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {
    self *= scalar
  }

  /// The square of this value.
  public var magnitudeSquared: Double {
    self * self
  }
}

extension Float: VectorArithmetic {
  /// Multiplies this value by a scalar.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {
    self *= Float(scalar)
  }

  /// The square of this value, represented as `Double`.
  public var magnitudeSquared: Double {
    Double(self * self)
  }
}

/// An animatable value with no components.
public struct EmptyAnimatableData: VectorArithmetic, Hashable {
  /// Creates empty animatable data.
  public init() {}

  /// The additive identity.
  public static let zero = EmptyAnimatableData()

  /// Returns the additive identity.
  /// - Complexity: O(1).
  public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData {
    .zero
  }

  /// Returns the additive identity.
  /// - Complexity: O(1).
  public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData {
    .zero
  }

  /// Leaves the empty value unchanged.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {}

  /// The zero squared magnitude.
  public var magnitudeSquared: Double {
    0
  }
}

/// A vector composed of two vector values.
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
  /// The first vector component.
  public var first: First
  /// The second vector component.
  public var second: Second

  /// Creates a pair from two vector components.
  public init(_ first: First, _ second: Second) {
    self.first = first
    self.second = second
  }

  /// The additive identity for both components.
  public static var zero: AnimatablePair<First, Second> {
    AnimatablePair(.zero, .zero)
  }

  /// Adds corresponding components.
  /// - Complexity: O(1) for fixed-size components.
  public static func + (
    lhs: AnimatablePair<First, Second>,
    rhs: AnimatablePair<First, Second>
  ) -> AnimatablePair<First, Second> {
    AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second)
  }

  /// Subtracts corresponding components.
  /// - Complexity: O(1) for fixed-size components.
  public static func - (
    lhs: AnimatablePair<First, Second>,
    rhs: AnimatablePair<First, Second>
  ) -> AnimatablePair<First, Second> {
    AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second)
  }

  /// Multiplies both components by a scalar.
  /// - Complexity: O(1) for fixed-size components.
  public mutating func scale(by scalar: Double) {
    first.scale(by: scalar)
    second.scale(by: scalar)
  }

  /// The sum of both squared component magnitudes.
  public var magnitudeSquared: Double {
    first.magnitudeSquared + second.magnitudeSquared
  }
}

extension AnimatablePair: Hashable where First: Hashable, Second: Hashable {}
