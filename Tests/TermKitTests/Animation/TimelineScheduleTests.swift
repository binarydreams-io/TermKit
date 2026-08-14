@testable import TermKit
import Testing

struct TimelineScheduleTests {
  @Test
  func `Periodic timeline aligns entries to its origin`() {
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

  @Test
  func `Explicit timeline sorts and deduplicates instants`() {
    let schedule = TimelineSchedule.explicit([
      TimeInstant(nanoseconds: 30),
      TimeInstant(nanoseconds: 10),
      TimeInstant(nanoseconds: 30),
      TimeInstant(nanoseconds: 20)
    ])

    #expect(
      schedule.entries(from: .zero, through: TimeInstant(nanoseconds: 30))
        == [
          TimeInstant(nanoseconds: 10),
          TimeInstant(nanoseconds: 20),
          TimeInstant(nanoseconds: 30)
        ]
    )
    #expect(schedule.next(after: TimeInstant(nanoseconds: 30)) == nil)
  }

  @Test
  func `Animation timeline never exceeds sixty frames per second`() {
    let schedule = TimelineSchedule.animation(minimumInterval: .milliseconds(1))

    #expect(schedule.cadence == FrameScheduler.minimumFrameInterval)
    #expect(schedule.next(after: .zero) == .zero.advanced(by: FrameScheduler.minimumFrameInterval))
  }
}
