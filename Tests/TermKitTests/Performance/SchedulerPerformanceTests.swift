@testable import TermKit
import Testing

@MainActor
@Suite(
  "Section 15 scheduler contracts",
  .disabled(
    if: termKitPerformanceTestsEnabled == false,
    "Set TERMKIT_RUN_PERFORMANCE_TESTS=1 and use a release build."
  )
)
struct SchedulerPerformanceTests {
  @Test
  func `Sustained invalidations coalesce into one frame`() throws {
    let harness = try RuntimeFrameHarness(size: CellSize(width: 120, height: 40))
    harness.view.prepareLocalizedFrame(
      index: 0,
      rect: CellRect(x: 0, y: 0, width: 1, height: 1)
    )
    for _ in 0 ..< 100000 {
      harness.runtime.invalidate(.region(CellRect(x: 0, y: 0, width: 1, height: 1)))
    }

    let frame = try harness.renderNextFrame()

    #expect(frame.presentation.stats.scannedCellCount == 1)
    #expect(harness.view.paintCount == 1)
    #expect(harness.session.logicalWriteCount == 1)
    #expect(try harness.runtime.renderIfDue(at: harness.instant) == nil)
    #expect(harness.runtime.scheduler.isIdle)
  }

  @Test
  func `A stalled animation does not queue stale frames`() throws {
    let scheduler = FrameScheduler(maximumDeltaTime: .milliseconds(50))
    scheduler.register("animation")
    _ = try #require(scheduler.frame(at: .zero))
    let stalledInstant = TimeInstant.zero.advanced(by: .seconds(2))

    let current = try #require(scheduler.frame(at: stalledInstant))

    #expect(current.deltaTime == .milliseconds(50))
    #expect(scheduler.frame(at: stalledInstant) == nil)
    #expect(
      scheduler.nextDeadline(at: stalledInstant)
        == stalledInstant.advanced(by: FrameScheduler.minimumFrameInterval)
    )
  }

  @Test
  func `An idle scheduler has no frame or deadline`() {
    let scheduler = FrameScheduler()

    #expect(scheduler.isIdle)
    #expect(scheduler.nextDeadline(at: .zero) == nil)
    #expect(scheduler.frame(at: .zero) == nil)
  }
}
