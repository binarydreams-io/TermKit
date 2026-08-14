import Testing

@testable import TermKit

struct TimeTests {
    @Test func deterministicTimeAdvancesSynchronously() {
        var clock = DeterministicTimeSource(now: TimeInstant(nanoseconds: 10))

        clock.advance(by: .milliseconds(2))

        #expect(clock.now == TimeInstant(nanoseconds: 2_000_010))
        #expect(TimeInstant.zero.duration(to: clock.now) == .nanoseconds(2_000_010))
    }

    @Test func durationConvertsFractionalSeconds() {
        #expect(TimeSpan.seconds(1.25) == .milliseconds(1_250))
        #expect(TimeSpan.milliseconds(250).seconds == 0.25)
    }
}
