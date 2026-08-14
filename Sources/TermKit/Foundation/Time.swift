/// A signed duration with nanosecond precision.
public struct TimeSpan: Sendable, Hashable, Comparable {
  /// The duration in nanoseconds.
  public var nanoseconds: Int64

  /// Creates a duration from nanoseconds.
  public init(nanoseconds: Int64) {
    self.nanoseconds = nanoseconds
  }

  /// A duration of zero.
  public static let zero = TimeSpan(nanoseconds: 0)

  /// Creates a duration from nanoseconds.
  public static func nanoseconds(_ value: Int64) -> TimeSpan {
    TimeSpan(nanoseconds: value)
  }

  /// Creates a duration from milliseconds.
  public static func milliseconds(_ value: Int64) -> TimeSpan {
    let (result, overflow) = value.multipliedReportingOverflow(by: 1000000)
    precondition(overflow == false, "Duration exceeds Int64 range.")
    return TimeSpan(nanoseconds: result)
  }

  /// Creates a duration from seconds.
  public static func seconds(_ value: Double) -> TimeSpan {
    precondition(value.isFinite, "Duration must be finite.")
    let nanoseconds = value * 1_000_000_000
    precondition(nanoseconds >= Double(Int64.min) && nanoseconds <= Double(Int64.max), "Duration exceeds Int64 range.")
    return TimeSpan(nanoseconds: Int64(nanoseconds.rounded()))
  }

  /// The duration in seconds.
  public var seconds: Double {
    Double(nanoseconds) / 1_000_000_000
  }

  /// Returns whether the left duration is shorter than the right duration.
  public static func < (lhs: TimeSpan, rhs: TimeSpan) -> Bool {
    lhs.nanoseconds < rhs.nanoseconds
  }

  /// Adds two durations.
  public static func + (lhs: TimeSpan, rhs: TimeSpan) -> TimeSpan {
    let (result, overflow) = lhs.nanoseconds.addingReportingOverflow(rhs.nanoseconds)
    precondition(overflow == false, "Duration exceeds Int64 range.")
    return TimeSpan(nanoseconds: result)
  }

  /// Subtracts one duration from another.
  public static func - (lhs: TimeSpan, rhs: TimeSpan) -> TimeSpan {
    let (result, overflow) = lhs.nanoseconds.subtractingReportingOverflow(rhs.nanoseconds)
    precondition(overflow == false, "Duration exceeds Int64 range.")
    return TimeSpan(nanoseconds: result)
  }
}

/// A time value measured in nanoseconds from a source-defined origin.
public struct TimeInstant: Sendable, Hashable, Comparable {
  /// The offset from the source-defined origin, in nanoseconds.
  public var nanoseconds: Int64

  /// Creates a time instant from a nanosecond offset.
  public init(nanoseconds: Int64) {
    self.nanoseconds = nanoseconds
  }

  /// The instant at the source-defined origin.
  public static let zero = TimeInstant(nanoseconds: 0)

  /// Returns an instant advanced by a duration.
  public func advanced(by duration: TimeSpan) -> TimeInstant {
    let (result, overflow) = nanoseconds.addingReportingOverflow(duration.nanoseconds)
    precondition(overflow == false, "Time instant exceeds Int64 range.")
    return TimeInstant(nanoseconds: result)
  }

  /// Returns the duration from this instant to another instant.
  public func duration(to other: TimeInstant) -> TimeSpan {
    let (result, overflow) = other.nanoseconds.subtractingReportingOverflow(nanoseconds)
    precondition(overflow == false, "Duration exceeds Int64 range.")
    return TimeSpan(nanoseconds: result)
  }

  /// Returns whether the left instant precedes the right instant.
  public static func < (lhs: TimeInstant, rhs: TimeInstant) -> Bool {
    lhs.nanoseconds < rhs.nanoseconds
  }
}

/// A source of monotonic time instants.
public protocol TimeSource: Sendable {
  /// The current time instant.
  var now: TimeInstant { get }
}

/// A time source that advances only through explicit mutations.
public struct DeterministicTimeSource: TimeSource, Sendable, Hashable {
  /// The current time instant.
  public private(set) var current: TimeInstant

  /// Creates a deterministic time source at an initial instant.
  public init(now: TimeInstant = .zero) {
    self.current = now
  }

  /// The current time instant.
  public var now: TimeInstant {
    current
  }

  /// Advances the current instant by a nonnegative duration.
  public mutating func advance(by duration: TimeSpan) {
    precondition(duration >= .zero, "A deterministic clock cannot move backward.")
    current = current.advanced(by: duration)
  }

  /// Advances the current instant to a later instant.
  public mutating func advance(to instant: TimeInstant) {
    precondition(instant >= current, "A deterministic clock cannot move backward.")
    current = instant
  }
}

/// A time source backed by the system's continuous clock.
public struct ContinuousTimeSource: TimeSource, Sendable {
  private let clock: ContinuousClock
  private let origin: ContinuousClock.Instant

  /// Creates a time source with an origin at the current continuous-clock instant.
  public init() {
    let clock = ContinuousClock()
    self.clock = clock
    self.origin = clock.now
  }

  /// The elapsed time from this source's origin.
  public var now: TimeInstant {
    let components = origin.duration(to: clock.now).components
    let seconds = components.seconds
    let attoseconds = components.attoseconds
    let (secondNanoseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
    precondition(overflow == false, "Continuous clock duration exceeds Int64 range.")
    return TimeInstant(nanoseconds: secondNanoseconds + attoseconds / 1_000_000_000)
  }
}
