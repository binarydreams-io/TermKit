@testable import TermKit
import Testing

struct ConversationViewportTests {
  @Test
  func `Ten thousand transcript items produce only a small visible plan`() {
    var viewport = ConversationViewportState(
      viewportExtent: 20,
      itemExtent: 2,
      itemCount: 10000,
      overscan: 2,
      initiallyPinnedToBottom: false
    )
    viewport.scroll(to: 100)

    let plan = viewport.visiblePlan()

    #expect(plan.visibleRange == 48 ..< 62)
    #expect(plan.visibleRange.count == 14)
    #expect(plan.contentExtent == 20000)
  }

  @Test
  func `Prepending older messages preserves the visual anchor`() {
    var viewport = ConversationViewportState(
      viewportExtent: 30,
      itemExtent: 10,
      itemCount: 100,
      spacing: 1,
      initiallyPinnedToBottom: false
    )
    viewport.scroll(to: 55)
    let offsetBeforePrepend = viewport.scrollState.offset

    let anchor = viewport.prepend(itemCount: 3)

    #expect(anchor.previous.itemIndex == 5)
    #expect(anchor.resolved.itemIndex == 8)
    #expect(anchor.resolved.offsetFromViewportStart == anchor.previous.offsetFromViewportStart)
    #expect(viewport.scrollState.offset == offsetBeforePrepend + 33)
  }

  @Test
  func `New output stays pinned only while the user remains at the bottom`() {
    var viewport = ConversationViewportState(viewportExtent: 6, itemExtent: 2, itemCount: 10)

    viewport.append(itemCount: 1)
    #expect(viewport.isPinnedToBottom)
    #expect(viewport.scrollState.offset == 16)

    viewport.scroll(to: 10)
    viewport.append(itemCount: 1)
    #expect(viewport.isPinnedToBottom == false)
    #expect(viewport.scrollState.offset == 10)

    viewport.requestScrollToBottom()
    #expect(viewport.isPinnedToBottom)
    #expect(viewport.scrollState.offset == 18)
  }

  @Test
  func `Metric changes recalculate extent and preserve a visual anchor`() {
    var viewport = ConversationViewportState(
      viewportExtent: 10,
      itemExtent: 2,
      itemCount: 20,
      spacing: 1,
      initiallyPinnedToBottom: false
    )
    viewport.scroll(to: 7)
    let anchor = viewport.visualAnchor()

    viewport.updateMetrics(itemExtent: 4, spacing: 2, overscan: 3)

    #expect(viewport.scrollState.contentExtent == 118)
    #expect(viewport.visualAnchor() == anchor)
    #expect(viewport.overscan == 3)
  }

  @Test
  func `Metric changes keep a bottom-pinned viewport at the bottom`() {
    var viewport = ConversationViewportState(viewportExtent: 6, itemExtent: 2, itemCount: 10)

    viewport.updateMetrics(itemExtent: 3, spacing: 1, overscan: 2)

    #expect(viewport.scrollState.contentExtent == 39)
    #expect(viewport.scrollState.offset == 33)
    #expect(viewport.isPinnedToBottom)
  }

  @Test
  func `Measured message heights drive visibility and preserve anchors`() {
    var viewport = ConversationViewportState(
      viewportExtent: 5,
      itemExtent: 2,
      itemCount: 5,
      spacing: 1,
      overscan: 0,
      itemExtents: [1, 4, 2, 6, 1],
      initiallyPinnedToBottom: false
    )
    viewport.scroll(to: 3)

    #expect(viewport.visiblePlan().visibleRange == 1 ..< 3)
    #expect(viewport.visiblePlan().contentExtent == 18)
    let anchor = viewport.visualAnchor()

    viewport.updateItemExtents([1, 6, 2, 6, 1])

    #expect(viewport.visualAnchor() == anchor)
    #expect(viewport.scrollState.contentExtent == 20)
  }

  @Test
  @MainActor
  func `Viewport view adapter retains a bound state`() throws {
    final class Model {
      var state = ConversationViewportState(
        viewportExtent: 1,
        itemExtent: 1,
        itemCount: 3,
        initiallyPinnedToBottom: false
      )
    }
    let model = Model()
    let view = try AgentComponentView(
      items: ["one", "two", "three"],
      state: Binding(get: { model.state }, set: { model.state = $0 }),
      theme: SemanticTheme.standard.resolve(scheme: .dark)
    )

    #expect(view.graphBody.first?.primitive(as: (any ControlSemanticActionHandler).self) != nil)
  }
}
