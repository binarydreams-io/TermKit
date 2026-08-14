@testable import TermKit
import Testing

struct TimeTests {
  @Test func `deterministic time advances synchronously`() {
    var clock = DeterministicTimeSource(now: TimeInstant(nanoseconds: 10))

    clock.advance(by: .milliseconds(2))

    #expect(clock.now == TimeInstant(nanoseconds: 2000010))
    #expect(TimeInstant.zero.duration(to: clock.now) == .nanoseconds(2000010))
  }

  @Test func `duration converts fractional seconds`() {
    #expect(TimeSpan.seconds(1.25) == .milliseconds(1250))
    #expect(TimeSpan.milliseconds(250).seconds == 0.25)
  }
}
