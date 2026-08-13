public protocol VectorArithmetic: AdditiveArithmetic, Sendable {
    mutating func scale(by scalar: Double)
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    public func scaled(by scalar: Double) -> Self {
        var result = self
        result.scale(by: scalar)
        return result
    }

    public static func interpolated(from start: Self, to end: Self, progress: Double) -> Self {
        start + (end - start).scaled(by: progress)
    }
}

extension Double: VectorArithmetic {
    public mutating func scale(by scalar: Double) {
        self *= scalar
    }

    public var magnitudeSquared: Double {
        self * self
    }
}

extension Float: VectorArithmetic {
    public mutating func scale(by scalar: Double) {
        self *= Float(scalar)
    }

    public var magnitudeSquared: Double {
        Double(self * self)
    }
}

public struct EmptyAnimatableData: VectorArithmetic, Hashable {
    public init() {}

    public static let zero = EmptyAnimatableData()

    public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData {
        .zero
    }

    public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData {
        .zero
    }

    public mutating func scale(by scalar: Double) {}

    public var magnitudeSquared: Double { 0 }
}

public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: AnimatablePair<First, Second> {
        AnimatablePair(.zero, .zero)
    }

    public static func + (
        lhs: AnimatablePair<First, Second>,
        rhs: AnimatablePair<First, Second>
    ) -> AnimatablePair<First, Second> {
        AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (
        lhs: AnimatablePair<First, Second>,
        rhs: AnimatablePair<First, Second>
    ) -> AnimatablePair<First, Second> {
        AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by scalar: Double) {
        first.scale(by: scalar)
        second.scale(by: scalar)
    }

    public var magnitudeSquared: Double {
        first.magnitudeSquared + second.magnitudeSquared
    }
}

extension AnimatablePair: Hashable where First: Hashable, Second: Hashable {}
