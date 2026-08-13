public struct TUIDuration: Sendable, Hashable, Comparable {
    public var nanoseconds: Int64

    public init(nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }

    public static let zero = TUIDuration(nanoseconds: 0)

    public static func nanoseconds(_ value: Int64) -> TUIDuration {
        TUIDuration(nanoseconds: value)
    }

    public static func milliseconds(_ value: Int64) -> TUIDuration {
        let (result, overflow) = value.multipliedReportingOverflow(by: 1_000_000)
        precondition(overflow == false, "Duration exceeds Int64 range.")
        return TUIDuration(nanoseconds: result)
    }

    public static func seconds(_ value: Double) -> TUIDuration {
        precondition(value.isFinite, "Duration must be finite.")
        let nanoseconds = value * 1_000_000_000
        precondition(nanoseconds >= Double(Int64.min) && nanoseconds <= Double(Int64.max), "Duration exceeds Int64 range.")
        return TUIDuration(nanoseconds: Int64(nanoseconds.rounded()))
    }

    public var seconds: Double {
        Double(nanoseconds) / 1_000_000_000
    }

    public static func < (lhs: TUIDuration, rhs: TUIDuration) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    public static func + (lhs: TUIDuration, rhs: TUIDuration) -> TUIDuration {
        let (result, overflow) = lhs.nanoseconds.addingReportingOverflow(rhs.nanoseconds)
        precondition(overflow == false, "Duration exceeds Int64 range.")
        return TUIDuration(nanoseconds: result)
    }

    public static func - (lhs: TUIDuration, rhs: TUIDuration) -> TUIDuration {
        let (result, overflow) = lhs.nanoseconds.subtractingReportingOverflow(rhs.nanoseconds)
        precondition(overflow == false, "Duration exceeds Int64 range.")
        return TUIDuration(nanoseconds: result)
    }
}

public struct TimeInstant: Sendable, Hashable, Comparable {
    public var nanoseconds: Int64

    public init(nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }

    public static let zero = TimeInstant(nanoseconds: 0)

    public func advanced(by duration: TUIDuration) -> TimeInstant {
        let (result, overflow) = nanoseconds.addingReportingOverflow(duration.nanoseconds)
        precondition(overflow == false, "Time instant exceeds Int64 range.")
        return TimeInstant(nanoseconds: result)
    }

    public func duration(to other: TimeInstant) -> TUIDuration {
        let (result, overflow) = other.nanoseconds.subtractingReportingOverflow(nanoseconds)
        precondition(overflow == false, "Duration exceeds Int64 range.")
        return TUIDuration(nanoseconds: result)
    }

    public static func < (lhs: TimeInstant, rhs: TimeInstant) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

public protocol TimeSource: Sendable {
    func now() -> TimeInstant
}

public struct DeterministicTimeSource: TimeSource, Sendable, Hashable {
    public private(set) var current: TimeInstant

    public init(now: TimeInstant = .zero) {
        current = now
    }

    public func now() -> TimeInstant {
        current
    }

    public mutating func advance(by duration: TUIDuration) {
        precondition(duration >= .zero, "A deterministic clock cannot move backward.")
        current = current.advanced(by: duration)
    }

    public mutating func advance(to instant: TimeInstant) {
        precondition(instant >= current, "A deterministic clock cannot move backward.")
        current = instant
    }
}

public struct ContinuousTimeSource: TimeSource, Sendable {
    private let clock: ContinuousClock
    private let origin: ContinuousClock.Instant

    public init() {
        let clock = ContinuousClock()
        self.clock = clock
        origin = clock.now
    }

    public func now() -> TimeInstant {
        let components = origin.duration(to: clock.now).components
        let seconds = components.seconds
        let attoseconds = components.attoseconds
        let (secondNanoseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        precondition(overflow == false, "Continuous clock duration exceeds Int64 range.")
        return TimeInstant(nanoseconds: secondNanoseconds + attoseconds / 1_000_000_000)
    }
}
