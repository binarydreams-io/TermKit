@testable import TermKit
import Testing

@MainActor
@Suite("Layout")
struct LayoutTests {
  private enum Leaf {}

  @Test
  func `Declarative stacks retain indexed children and layout configuration`() throws {
    let vertical = try #require(
      VStack(alignment: .trailing, spacing: 2) {
        NodeDescriptor(type: Leaf.self, value: 1)
        NodeDescriptor(type: Leaf.self, value: 2)
      }.graphBody.first
    )
    let horizontal = try #require(
      HStack(alignment: .bottom, spacing: 3) {
        NodeDescriptor(type: Leaf.self)
      }.graphBody.first
    )

    #expect(vertical.identity == StructuralIdentity(type: VStack.self))
    #expect(vertical.children.map(\.identity.index) == [0, 1])
    #expect(vertical.dirtyOnUpdate == .layout)
    #expect(
      vertical.value(as: LayoutPrimitive.self)
        == .stack(
          StackLayout(axis: .vertical, spacing: 2, horizontalAlignment: .trailing)
        )
    )
    #expect(vertical.primitive(as: LayoutPrimitive.self) == vertical.value(as: LayoutPrimitive.self))
    #expect(
      horizontal.primitive(as: LayoutPrimitive.self)
        == .stack(
          StackLayout(axis: .horizontal, spacing: 3, verticalAlignment: .bottom)
        )
    )
  }

  @Test
  func `Layout modifiers wrap content and retain snapshots`() throws {
    let view = VStack {
      NodeDescriptor(type: Leaf.self)
    }
    .padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
    .frame(width: 12, height: 8, alignment: .bottomTrailing)
    let graph = ViewGraph()
    try graph.commit(graph.prepare(view))
    func descendants(of node: MountedNode) -> [MountedNode] {
      var pending = [node]
      var result: [MountedNode] = []
      while let current = pending.popLast() {
        result.append(current)
        pending.append(contentsOf: current.children)
      }
      return result
    }
    let layoutNodes: [(MountedNode, LayoutPrimitive)] = try descendants(of: #require(graph.root)).compactMap { node in
      node.primitive(as: LayoutPrimitive.self).map { (node, $0) }
    }
    let descriptor = try #require(
      layoutNodes.first { _, primitive in
        primitive == LayoutPrimitive.frame(FrameLayout(width: 12, height: 8, alignment: .bottomTrailing))
      }?.0
    )
    let padding = try #require(
      layoutNodes.first { _, primitive in
        primitive
          == LayoutPrimitive.padding(
            PaddingLayout(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
          )
      }?.0
    )

    #expect(descriptor.children.count == 1)
    #expect(
      descriptor.primitive(as: LayoutPrimitive.self)
        == .frame(
          FrameLayout(width: 12, height: 8, alignment: .bottomTrailing)
        )
    )
    #expect(descriptor.value(as: LayoutPrimitive.self) == descriptor.primitive(as: LayoutPrimitive.self))
    #expect(padding.children.count == 1)
    #expect(
      padding.primitive(as: LayoutPrimitive.self)
        == .padding(
          PaddingLayout(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        )
    )
  }

  @Test
  func `Declarative primitive configuration drives existing layout algorithms`() throws {
    let descriptor = try #require(
      VStack(alignment: .trailing, spacing: 1) {
        NodeDescriptor(type: Leaf.self)
        NodeDescriptor(type: Leaf.self)
      }.graphBody.first
    )
    let primitive = try #require(descriptor.primitive(as: LayoutPrimitive.self))
    let items = [
      LayoutItem(nodeID: NodeID(rawValue: 1), size: CellSize(width: 2, height: 1)),
      LayoutItem(nodeID: NodeID(rawValue: 2), size: CellSize(width: 4, height: 2))
    ]

    guard case let .stack(layout) = primitive else {
      Issue.record("Expected a stack layout primitive")
      return
    }
    let result = layout.layout(items, cache: LayoutCache())

    #expect(result.size == CellSize(width: 4, height: 4))
    #expect(
      result.placements.map(\.frame) == [
        CellRect(x: 2, y: 0, width: 2, height: 1),
        CellRect(x: 0, y: 2, width: 4, height: 2)
      ]
    )
  }

  @Test
  func `Vertical stack measures and aligns children`() {
    let cache = LayoutCache()
    let items = [
      LayoutItem(nodeID: NodeID(rawValue: 1), size: CellSize(width: 2, height: 1)),
      LayoutItem(nodeID: NodeID(rawValue: 2), size: CellSize(width: 4, height: 2))
    ]
    let result = StackLayout(axis: .vertical, spacing: 1, horizontalAlignment: .trailing)
      .layout(items, in: .unspecified, cache: cache)

    #expect(result.size == CellSize(width: 4, height: 4))
    #expect(result.placements[0].frame == CellRect(x: 2, y: 0, width: 2, height: 1))
    #expect(result.placements[1].frame == CellRect(x: 0, y: 2, width: 4, height: 2))
  }

  @Test
  func `Stack accepts representable geometry at the Int boundary`() {
    let items = [
      LayoutItem(nodeID: NodeID(rawValue: 1), size: CellSize(width: Int.max, height: 1))
    ]

    let result = StackLayout(axis: .horizontal, spacing: 1).layout(items, cache: LayoutCache())

    #expect(result.size.width == Int.max)
    #expect(result.placements[0].frame.maxX == Int.max)
  }

  @Test
  func `Overlay uses both alignment axes`() {
    let cache = LayoutCache()
    let item = LayoutItem(nodeID: NodeID(rawValue: 1), size: CellSize(width: 2, height: 1))
    let result = OverlayLayout(alignment: .bottomTrailing).layout(
      [item],
      in: ProposedCellSize(width: 6, height: 4),
      cache: cache
    )
    #expect(result.placements[0].frame.origin == CellPoint(x: 4, y: 3))
  }

  @Test
  func `Cache isolates measurements by node and proposal`() {
    let cache = LayoutCache()
    let item = LayoutItem(nodeID: NodeID(rawValue: 1)) { proposal in
      CellSize(width: proposal.width ?? 3, height: 1)
    }
    _ = cache.measure(item, in: ProposedCellSize(width: 4))
    _ = cache.measure(item, in: ProposedCellSize(width: 4))
    _ = cache.measure(item, in: ProposedCellSize(width: 5))
    #expect(cache.hitCount == 1)
    #expect(cache.missCount == 2)
  }

  @Test
  func `Mounted node layout invalidation advances the cache generation`() throws {
    enum Root {}
    let graph = ViewGraph()
    try graph.commit(graph.prepare(NodeDescriptor(type: Root.self)))
    let node = try #require(graph.root)
    node.cache(
      size: CellSize(width: 2, height: 1),
      frame: CellRect(x: 0, y: 0, width: 2, height: 1)
    )
    let item = LayoutItem(node: node) { _ in
      node.cachedSize ?? .zero
    }
    let cache = LayoutCache()

    #expect(cache.measure(item, in: .unspecified).width == 2)
    #expect(cache.measure(item, in: .unspecified).width == 2)
    node.cache(
      size: CellSize(width: 5, height: 1),
      frame: CellRect(x: 0, y: 0, width: 5, height: 1)
    )
    node.invalidate(.layout)
    #expect(cache.measure(item, in: .unspecified).width == 5)
    #expect(cache.hitCount == 1)
    #expect(cache.missCount == 2)
  }

  @Test
  func `Frame constrains a fixed axis before measuring the other axis`() {
    let item = LayoutItem(nodeID: NodeID(rawValue: 1)) { proposal in
      CellSize(width: proposal.width ?? 20, height: proposal.width == 4 ? 2 : 10)
    }
    let result = FrameLayout(width: 4).layout(item, in: .unspecified, cache: LayoutCache())

    #expect(result.size == CellSize(width: 4, height: 2))
    #expect(result.placements[0].frame.size == CellSize(width: 4, height: 2))
  }

  @Test
  func `Disjoint nested clips produce an empty clip`() {
    let result = LayoutResult(
      size: CellSize(width: 10, height: 1),
      placements: [
        LayoutPlacement(
          nodeID: NodeID(rawValue: 1),
          frame: CellRect(x: 0, y: 0, width: 2, height: 1),
          clip: CellRect(x: 0, y: 0, width: 2, height: 1)
        )
      ]
    )

    let nested = result.clipped(to: CellRect(x: 5, y: 0, width: 2, height: 1))

    #expect(nested.placements[0].clip?.isEmpty == true)
  }

  @Test
  func `Lazy plan instantiates only a bounded visible range`() {
    let plan = LazyLayoutPlanner(itemExtent: 1, overscan: 2)
      .plan(itemCount: 10000, viewport: 5000 ..< 5040)
    #expect(plan.visibleRange == 4998 ..< 5042)
    #expect(plan.visibleRange.count == 44)
    #expect(plan.contentExtent == 10000)
  }

  @Test
  func `Lazy plan returns empty ranges for empty and out-of-content viewports`() {
    let planner = LazyLayoutPlanner(itemExtent: 1)

    #expect(planner.plan(itemCount: 10, viewport: 5 ..< 5).visibleRange == 5 ..< 5)
    #expect(planner.plan(itemCount: 10, viewport: 20 ..< 30).visibleRange == 10 ..< 10)
    #expect(
      LazyLayoutPlanner(itemExtent: 1, spacing: 1)
        .plan(itemCount: 10, viewport: 19 ..< 19).visibleRange == 10 ..< 10
    )
    #expect(planner.plan(itemCount: 0, viewport: 20 ..< 30).visibleRange == 0 ..< 0)
  }

  @Test
  func `Prepend correction preserves the visual anchor`() {
    var state = ScrollState(viewportExtent: 10, contentExtent: 100, offset: 20)
    state.contentExtent = 105
    state.preserveAnchor(oldOrigin: 20, newOrigin: 25)
    #expect(state.offset == 25)
  }

  @Test
  func `Bottom anchoring stops after the user scrolls away`() {
    var pinned = ScrollState(viewportExtent: 10, contentExtent: 100, offset: 90)
    pinned.updateContentExtent(120, anchorToBottom: true)
    #expect(pinned.offset == 110)

    var detached = ScrollState(viewportExtent: 10, contentExtent: 100, offset: 80)
    detached.updateContentExtent(120, anchorToBottom: true)
    #expect(detached.offset == 80)
  }
}
