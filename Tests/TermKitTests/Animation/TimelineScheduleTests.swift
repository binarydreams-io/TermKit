import Testing

@testable import TermKit

struct TimelineScheduleTests {
    @Test("Periodic timeline aligns entries to its origin")
    func periodic() {
        let schedule = TimelineSchedule.periodic(
            from: TimeInstant(nanoseconds: 10),
            by: .nanoseconds(10)
        )

        #expect(schedule.next(after: TimeInstant(nanoseconds: 15)) == TimeInstant(nanoseconds: 20))
        #expect(
            schedule.entries(from: TimeInstant(nanoseconds: 15), through: TimeInstant(nanoseconds: 35))
                == [TimeInstant(nanoseconds: 20), TimeInstant(nanoseconds: 30)]
        )
    }

    @Test("Explicit timeline sorts and deduplicates instants")
    func explicit() {
        let schedule = TimelineSchedule.explicit([
            TimeInstant(nanoseconds: 30),
            TimeInstant(nanoseconds: 10),
            TimeInstant(nanoseconds: 30),
            TimeInstant(nanoseconds: 20),
        ])

        #expect(
            schedule.entries(from: .zero, through: TimeInstant(nanoseconds: 30))
                == [
                    TimeInstant(nanoseconds: 10),
                    TimeInstant(nanoseconds: 20),
                    TimeInstant(nanoseconds: 30),
                ]
        )
        #expect(schedule.next(after: TimeInstant(nanoseconds: 30)) == nil)
    }

    @Test("Animation timeline never exceeds sixty frames per second")
    func animation() {
        let schedule = TimelineSchedule.animation(minimumInterval: .milliseconds(1))

        #expect(schedule.cadence == FrameScheduler.minimumFrameInterval)
        #expect(schedule.next(after: .zero) == .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    }
}
