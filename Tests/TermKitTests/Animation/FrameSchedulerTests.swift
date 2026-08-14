import Testing

@testable import TermKit

@MainActor
struct FrameSchedulerTests {
    @Test("Idle scheduler has no deadline")
    func idle() {
        let scheduler = FrameScheduler()

        #expect(scheduler.isIdle)
        #expect(scheduler.nextDeadline(at: .zero) == nil)
        #expect(scheduler.frame(at: .zero) == nil)
    }

    @Test("Scheduler respects a lower requested cadence")
    func lowerCadence() throws {
        let scheduler = FrameScheduler()
        scheduler.register("spinner", cadence: .milliseconds(100))

        let first = try #require(scheduler.frame(at: .zero))
        let early = scheduler.frame(at: .zero.advanced(by: .milliseconds(99)))
        let second = try #require(scheduler.frame(at: .zero.advanced(by: .milliseconds(100))))

        #expect(first.deltaTime == .zero)
        #expect(early == nil)
        #expect(second.deltaTime == .milliseconds(100))
    }

    @Test("Scheduler caps demand at sixty frames per second")
    func maximumCadence() throws {
        let scheduler = FrameScheduler()
        scheduler.register("animation", cadence: .milliseconds(1))
        _ = scheduler.frame(at: .zero)

        let deadline = try #require(scheduler.nextDeadline(at: .zero))

        #expect(deadline == .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    }

    @Test("Scheduler coalesces invalidation and clamps stale delta")
    func coalescingAndClamping() throws {
        let scheduler = FrameScheduler(maximumDeltaTime: .milliseconds(50))
        scheduler.requestFrame()
        scheduler.requestFrame()
        _ = try #require(scheduler.frame(at: .zero))

        scheduler.requestFrame()
        let stalled = try #require(scheduler.frame(at: .zero.advanced(by: .seconds(2))))

        #expect(stalled.deltaTime == .milliseconds(50))
        #expect(scheduler.isIdle)
        #expect(scheduler.frame(at: .zero.advanced(by: .seconds(2))) == nil)
    }

    @Test("Scheduler does not replay missed demand frames")
    func noStaleQueue() throws {
        let scheduler = FrameScheduler()
        scheduler.register("animation")
        _ = try #require(scheduler.frame(at: .zero))
        let stalledInstant = TimeInstant.zero.advanced(by: .seconds(2))

        _ = try #require(scheduler.frame(at: stalledInstant))

        #expect(scheduler.frame(at: stalledInstant) == nil)
        #expect(
            scheduler.nextDeadline(at: stalledInstant)
                == stalledInstant.advanced(by: FrameScheduler.minimumFrameInterval)
        )
    }
}
