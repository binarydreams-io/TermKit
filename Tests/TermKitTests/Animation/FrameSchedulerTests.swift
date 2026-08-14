@testable import TermKit
import Testing

@MainActor
struct FrameSchedulerTests {
  @Test
  func `Idle scheduler has no deadline`() {
    let scheduler = FrameScheduler()

    #expect(scheduler.isIdle)
    #expect(scheduler.nextDeadline(at: .zero) == nil)
    #expect(scheduler.frame(at: .zero) == nil)
  }

  @Test
  func `Scheduler respects a lower requested cadence`() throws {
    let scheduler = FrameScheduler()
    scheduler.register("spinner", cadence: .milliseconds(100))

    let first = try #require(scheduler.frame(at: .zero))
    let early = scheduler.frame(at: .zero.advanced(by: .milliseconds(99)))
    let second = try #require(scheduler.frame(at: .zero.advanced(by: .milliseconds(100))))

    #expect(first.deltaTime == .zero)
    #expect(early == nil)
    #expect(second.deltaTime == .milliseconds(100))
  }

  @Test
  func `Scheduler caps demand at sixty frames per second`() throws {
    let scheduler = FrameScheduler()
    scheduler.register("animation", cadence: .milliseconds(1))
    _ = scheduler.frame(at: .zero)

    let deadline = try #require(scheduler.nextDeadline(at: .zero))

    #expect(deadline == .zero.advanced(by: FrameScheduler.minimumFrameInterval))
  }

  @Test
  func `Scheduler coalesces invalidation and clamps stale delta`() throws {
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

  @Test
  func `Scheduler does not replay missed demand frames`() throws {
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
