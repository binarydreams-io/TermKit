@testable import TermKit
import Testing

@MainActor
struct TimelineViewTests {
  @Test
  func `Timeline view evaluates content at the supplied instant`() throws {
    let instant = TimeInstant(nanoseconds: 25)
    let view = TimelineView(.periodic(from: .zero, by: .nanoseconds(10)), at: instant) { context in
      DescriptorView(NodeDescriptor(type: TimelineViewTests.self, value: context.instant))
    }

    let descriptor = try #require(view.graphBody.first)

    #expect(descriptor.value(as: TimeInstant.self) == instant)
    #expect(view.nextUpdate(after: instant) == TimeInstant(nanoseconds: 30))
  }

  @Test
  func `Timeline context exposes animation cadence`() {
    let view = TimelineView(.animation(), at: .zero) { context in
      DescriptorView(NodeDescriptor(type: TimelineViewTests.self, value: context.cadence))
    }

    #expect(view.content(at: .zero).descriptor.value(as: TimeSpan.self) == FrameScheduler.minimumFrameInterval)
  }

  @Test
  func `Explicit timeline stops after its last instant`() {
    let view = TimelineView(
      .explicit([TimeInstant(nanoseconds: 10)]),
      at: .zero
    ) { _ in
      DescriptorView(NodeDescriptor(type: TimelineViewTests.self))
    }

    #expect(view.nextUpdate(after: TimeInstant(nanoseconds: 10)) == nil)
  }

  @Test
  func `Declarative timeline mounts a frame demand`() throws {
    let graph = ViewGraph()
    let view = TimelineView(.periodic(from: .zero, by: .nanoseconds(10))) { context in
      DescriptorView(NodeDescriptor(type: TimelineViewTests.self, value: context.instant))
    }
    try graph.commit(graph.prepare(view))

    let sampling = graph.sampleMountedAttributesDeferringCompletions(at: .zero)

    #expect(sampling.frameDemand == MountedFrameDemand(deadline: TimeInstant(nanoseconds: 10)))
  }
}
