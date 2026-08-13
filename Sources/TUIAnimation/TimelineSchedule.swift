import TUIFoundation

public struct TimelineSchedule: Sendable, Hashable {
    package enum Kind {
        case animation
        case periodic
        case explicit
    }

    private enum Storage: Sendable, Hashable {
        case animation(minimumInterval: TUIDuration)
        case periodic(from: TimeInstant, interval: TUIDuration)
        case explicit([TimeInstant])
    }

    private let storage: Storage

    package var kind: Kind {
        switch storage {
        case .animation: .animation
        case .periodic: .periodic
        case .explicit: .explicit
        }
    }

    public static func animation(
        minimumInterval: TUIDuration = FrameScheduler.minimumFrameInterval
    ) -> TimelineSchedule {
        precondition(minimumInterval > .zero, "A timeline interval must be positive.")
        return TimelineSchedule(storage: .animation(minimumInterval: max(minimumInterval, FrameScheduler.minimumFrameInterval)))
    }

    public static func periodic(from start: TimeInstant, by interval: TUIDuration) -> TimelineSchedule {
        precondition(interval > .zero, "A periodic timeline interval must be positive.")
        return TimelineSchedule(storage: .periodic(from: start, interval: interval))
    }

    public static func explicit(_ instants: [TimeInstant]) -> TimelineSchedule {
        TimelineSchedule(storage: .explicit(Array(Set(instants)).sorted()))
    }

    public var cadence: TUIDuration? {
        switch storage {
        case .animation(let minimumInterval): minimumInterval
        case .periodic(_, let interval): interval
        case .explicit: nil
        }
    }

    public func next(after instant: TimeInstant) -> TimeInstant? {
        switch storage {
        case .animation(let minimumInterval):
            return instant.advanced(by: minimumInterval)
        case .periodic(let start, let interval):
            if instant < start { return start }
            let elapsed = start.duration(to: instant).nanoseconds
            let (periods, overflow) = (elapsed / interval.nanoseconds).addingReportingOverflow(1)
            precondition(overflow == false, "A timeline instant exceeds the supported range.")
            return start.advanced(by: multiplied(interval, by: periods))
        case .explicit(let instants):
            return instants.first { $0 > instant }
        }
    }

    public func entries(from start: TimeInstant, through end: TimeInstant) -> [TimeInstant] {
        guard start <= end else { return [] }

        switch storage {
        case .animation(let interval):
            return stridedEntries(first: start, interval: interval, through: end)
        case .periodic(let origin, let interval):
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
        case .explicit(let instants):
            return instants.filter { $0 >= start && $0 <= end }
        }
    }

    private func stridedEntries(
        first: TimeInstant,
        interval: TUIDuration,
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

    private func multiplied(_ duration: TUIDuration, by count: Int64) -> TUIDuration {
        let (nanoseconds, overflow) = duration.nanoseconds.multipliedReportingOverflow(by: count)
        precondition(overflow == false, "A timeline instant exceeds the supported range.")
        return .nanoseconds(nanoseconds)
    }
}
