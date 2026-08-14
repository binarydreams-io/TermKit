/// A source of instants for timeline-driven content.
public struct TimelineSchedule: Sendable, Hashable {
  enum Kind {
    case animation
    case periodic
    case explicit
  }

  private enum Storage: Sendable, Hashable {
    case animation(minimumInterval: TimeSpan)
    case periodic(from: TimeInstant, interval: TimeSpan)
    case explicit([TimeInstant])
  }

  private let storage: Storage

  var kind: Kind {
    switch storage {
    case .animation: .animation
    case .periodic: .periodic
    case .explicit: .explicit
    }
  }

  /// Creates a schedule that follows the animation frame cadence.
  /// - Complexity: O(1).
  public static func animation(
    minimumInterval: TimeSpan = FrameScheduler.minimumFrameInterval
  ) -> TimelineSchedule {
    precondition(minimumInterval > .zero, "A timeline interval must be positive.")
    return TimelineSchedule(storage: .animation(minimumInterval: max(minimumInterval, FrameScheduler.minimumFrameInterval)))
  }

  /// Creates a periodic schedule from an origin and interval.
  /// - Complexity: O(1).
  public static func periodic(from start: TimeInstant, by interval: TimeSpan) -> TimelineSchedule {
    precondition(interval > .zero, "A periodic timeline interval must be positive.")
    return TimelineSchedule(storage: .periodic(from: start, interval: interval))
  }

  /// Creates a sorted schedule from unique explicit instants.
  /// - Complexity: O(n log n), where n is the instant count.
  public static func explicit(_ instants: [TimeInstant]) -> TimelineSchedule {
    TimelineSchedule(storage: .explicit(Array(Set(instants)).sorted()))
  }

  /// The preferred interval between entries, if one exists.
  public var cadence: TimeSpan? {
    switch storage {
    case let .animation(minimumInterval): minimumInterval
    case let .periodic(_, interval): interval
    case .explicit: nil
    }
  }

  /// Returns the first scheduled instant after an instant.
  /// - Complexity: O(n) for explicit schedules and O(1) otherwise.
  public func next(after instant: TimeInstant) -> TimeInstant? {
    switch storage {
    case let .animation(minimumInterval):
      return instant.advanced(by: minimumInterval)
    case let .periodic(start, interval):
      if instant < start {
        return start
      }
      let elapsed = start.duration(to: instant).nanoseconds
      let (periods, overflow) = (elapsed / interval.nanoseconds).addingReportingOverflow(1)
      precondition(overflow == false, "A timeline instant exceeds the supported range.")
      return start.advanced(by: multiplied(interval, by: periods))
    case let .explicit(instants):
      return instants.first { $0 > instant }
    }
  }

  /// Returns all scheduled instants in a closed range.
  /// - Complexity: O(n), where n is the entries examined or produced.
  public func entries(from start: TimeInstant, through end: TimeInstant) -> [TimeInstant] {
    guard start <= end else { return [] }

    switch storage {
    case let .animation(interval):
      return stridedEntries(first: start, interval: interval, through: end)
    case let .periodic(origin, interval):
      let first: TimeInstant
      if start <= origin {
        first = origin
      } else {
        let elapsed = origin.duration(to: start).nanoseconds
        let periods =
          elapsed / interval.nanoseconds
            + (elapsed.isMultiple(of: interval.nanoseconds) ? 0 : 1)
        first = origin.advanced(by: multiplied(interval, by: periods))
      }
      return stridedEntries(first: first, interval: interval, through: end)
    case let .explicit(instants):
      return instants.filter { $0 >= start && $0 <= end }
    }
  }

  private func stridedEntries(
    first: TimeInstant,
    interval: TimeSpan,
    through end: TimeInstant
  ) -> [TimeInstant] {
    guard first <= end else { return [] }
    var result: [TimeInstant] = []
    var instant = first
    while instant <= end {
      result.append(instant)
      guard instant < end, instant.duration(to: end) >= interval else { break }
      instant = instant.advanced(by: interval)
    }
    return result
  }

  private func multiplied(_ duration: TimeSpan, by count: Int64) -> TimeSpan {
    let (nanoseconds, overflow) = duration.nanoseconds.multipliedReportingOverflow(by: count)
    precondition(overflow == false, "A timeline instant exceeds the supported range.")
    return .nanoseconds(nanoseconds)
  }
}
