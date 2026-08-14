@testable import TermKit
import Testing

@MainActor
struct PresentationPropertyTests {
  private enum Root {}
  private enum Leaf {}

  @Test
  func `The property catalog exposes stable keys, types, and invalidation classes`() {
    expect(.foregroundColor, key: "foreground.color", dirtyFlags: .paint)
    expect(.backgroundColor, key: "background.color", dirtyFlags: .paint)
    expect(.borderColor, key: "border.color", dirtyFlags: .paint)
    expect(.opacity, key: "opacity", dirtyFlags: .paint)
    expect(.offset, key: "offset", dirtyFlags: .layout)
    expect(.frameWidth, key: "frame.width", dirtyFlags: .layout)
    expect(.frameHeight, key: "frame.height", dirtyFlags: .layout)
    expect(.padding, key: "padding", dirtyFlags: .layout)
    expect(.spacing, key: "spacing", dirtyFlags: .layout)
    expect(.clipInsets, key: "clip.insets", dirtyFlags: .layout)
    expect(.clipReveal, key: "clip.reveal", dirtyFlags: .layout)
    expect(.selectionHighlight, key: "selection.highlight", dirtyFlags: .paint)
    expect(.focusHighlight, key: "focus.highlight", dirtyFlags: .paint)
    expect(.scrollPosition, key: "scroll.position", dirtyFlags: .layout)
    expect(.transitionVisibility, key: "transition.visibility", dirtyFlags: .paint)
  }

  @Test
  func `Presentation vectors permit intermediate arithmetic values`() {
    #expect(CellVector.interpolated(from: .zero, to: CellVector(x: 3, y: -1), progress: 0.5) == CellVector(x: 1.5, y: -0.5))
    #expect(
      CellDimensions.interpolated(from: .zero, to: CellDimensions(width: 3, height: -1), progress: 0.5)
        == CellDimensions(width: 1.5, height: -0.5)
    )
    #expect(
      FloatingEdgeInsets.interpolated(
        from: .zero,
        to: FloatingEdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
        progress: 0.5
      ) == FloatingEdgeInsets(top: 0.5, leading: 1, bottom: 1.5, trailing: 2)
    )
  }

  @Test
  func `Presentation target validation rejects every non-finite component`() {
    var color = LinearRGBA.zero
    color.blue = .infinity
    var vector = CellVector.zero
    vector.x = .nan
    var dimensions = CellDimensions.zero
    dimensions.height = -.infinity
    var insets = FloatingEdgeInsets.zero
    insets.trailing = .nan

    #expect(presentationValueIsFinite(1.5))
    #expect(presentationValueIsFinite(LinearRGBA.zero))
    #expect(presentationValueIsFinite(CellVector.zero))
    #expect(presentationValueIsFinite(CellDimensions.zero))
    #expect(presentationValueIsFinite(FloatingEdgeInsets.zero))
    #expect(presentationValueIsFinite(Double.nan) == false)
    #expect(presentationValueIsFinite(Double.infinity) == false)
    #expect(presentationValueIsFinite(color) == false)
    #expect(presentationValueIsFinite(vector) == false)
    #expect(presentationValueIsFinite(dimensions) == false)
    #expect(presentationValueIsFinite(insets) == false)
  }

  @Test
  func `Linear color interpolation produces an sRGB midpoint near 188`() {
    let midpoint = LinearRGBA.interpolated(
      from: LinearRGBA(.black),
      to: LinearRGBA(.white),
      progress: 0.5
    ).rgba

    #expect(midpoint.redByte == 188)
    #expect(midpoint.greenByte == 188)
    #expect(midpoint.blueByte == 188)
  }

  @Test
  func `A static typed property retains its target without an active animation`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(NodeDescriptor(type: Leaf.self).presentationValue(0.75, for: .opacity)))
    let node = try #require(graph.root)

    #expect(node.presentationValue(.opacity) == 0.75)
    #expect(node.presentationValue(.opacity, at: .zero) == 0.75)
    #expect(node.animationStatus(for: .opacity) == .completed)
  }

  @Test
  func `Typed tracks interpolate and retarget from their sampled presentation`() throws {
    let graph = ViewGraph()
    try commit(value: 0, property: .opacity, to: graph, transaction: Transaction(animationTime: .zero))
    try commit(
      value: 10,
      property: .opacity,
      to: graph,
      transaction: Transaction(animation: .linear(duration: .seconds(1)), animationTime: .zero)
    )
    let node = try #require(graph.root)
    let midpoint = TimeInstant.zero.advanced(by: .milliseconds(500))

    #expect(node.presentationValue(.opacity, at: midpoint) == 5)
    try commit(
      value: 20,
      property: .opacity,
      to: graph,
      transaction: Transaction(animation: .linear(duration: .seconds(1)), animationTime: midpoint)
    )
    #expect(node.presentationValue(.opacity, at: midpoint) == 5)
  }

  @Test
  func `Sampling propagates property flags without calling the invalidation handler`() throws {
    var invalidationCount = 0
    let graph = ViewGraph { _, _ in invalidationCount += 1 }
    try commitChild(offset: .zero, opacity: 0, to: graph, transaction: Transaction(animationTime: .zero))
    try commitChild(
      offset: CellVector(x: 10, y: 0),
      opacity: 1,
      to: graph,
      transaction: Transaction(animation: .linear(duration: .seconds(1)), animationTime: .zero)
    )
    let child = try #require(graph.root?.children.first)
    graph.clearDirtyFlags()

    #expect(graph.sampleMountedAttributes(at: .zero.advanced(by: .milliseconds(500))) == 2)
    #expect(child.dirtyFlags == .layout)
    #expect(graph.root?.dirtyFlags == .layout)
    #expect(invalidationCount == 0)
  }

  @Test
  func `A completing sample invalidates its final frame without scheduling another frame`() throws {
    let graph = ViewGraph()
    try commit(value: 0, property: .opacity, to: graph, transaction: Transaction(animationTime: .zero))
    try commit(
      value: 1,
      property: .opacity,
      to: graph,
      transaction: Transaction(animation: .linear(duration: .seconds(1)), animationTime: .zero)
    )
    graph.clearDirtyFlags()

    #expect(graph.sampleMountedAttributes(at: .zero.advanced(by: .seconds(1))) == 0)
    #expect(graph.root?.dirtyFlags == .paint)
  }

  @Test
  func `Rollback restores an ordinary property's sampled value and running status`() throws {
    let graph = ViewGraph()
    try commit(value: 0, property: .opacity, to: graph, transaction: Transaction(animationTime: .zero))
    try commit(
      value: 1,
      property: .opacity,
      to: graph,
      transaction: Transaction(animation: .linear(duration: .seconds(1)), animationTime: .zero)
    )
    let node = try #require(graph.root)
    let frame = try graph.beginCommit(
      graph.prepare(
        NodeDescriptor(type: Leaf.self).presentationValue(1.0, for: .opacity)
      )
    )

    _ = graph.sampleMountedAttributesDeferringCompletions(at: .zero.advanced(by: .milliseconds(500)))
    #expect(node.presentationValue(.opacity, at: .zero.advanced(by: .milliseconds(500))) == 0.5)
    try graph.rollbackCommit(frame)

    #expect(node.animationStatus(for: .opacity) == .running)
    #expect(node.presentationValue(.opacity, at: .zero) == 0)
  }

  @Test
  func `A completed removal rolls back before completion and succeeds once on retry`() throws {
    let graph = ViewGraph()
    let transition = NodeDescriptor(type: Leaf.self).transition(.opacity)
    let insertionTransaction = Transaction(
      animation: .linear(duration: .seconds(1)),
      animationTime: .zero
    )
    try withTransaction(insertionTransaction) {
      try graph.commit(graph.prepare(transition))
    }
    let node = try #require(graph.root)
    let insertion = graph.sampleMountedAttributesDeferringCompletions(at: .zero.advanced(by: .seconds(1)))
    for action in insertion.completionActions {
      action()
    }
    #expect(node.presentationPhase == .active)

    var completionCount = 0
    let removalTransaction = Transaction(
      animation: .linear(duration: .seconds(1)),
      completion: { completionCount += 1 },
      animationTime: .zero.advanced(by: .seconds(1))
    )
    try withTransaction(removalTransaction) {
      try graph.commit(graph.prepare(nil))
    }
    #expect(graph.presentationNode(withID: node.id) === node)

    let failedFrame = try graph.beginCommit(graph.prepare(nil))
    let failedSample = graph.sampleMountedAttributesDeferringCompletions(
      at: .zero.advanced(by: .seconds(2))
    )
    #expect(failedSample.completionActions.isEmpty == false)
    try graph.rollbackCommit(failedFrame)

    #expect(graph.presentationNode(withID: node.id) === node)
    #expect(node.animationStatus(for: .transitionVisibility) == .running)
    #expect(completionCount == 0)

    let retry = try graph.beginCommit(graph.prepare(nil))
    let retrySample = graph.sampleMountedAttributesDeferringCompletions(
      at: .zero.advanced(by: .seconds(2))
    )
    let commitActions = try graph.finishCommitDeferringCompletions(retry)
    for action in commitActions + retrySample.completionActions {
      action()
    }

    #expect(graph.presentationNode(withID: node.id) == nil)
    #expect(completionCount == 1)
  }

  @Test
  func `Disabled animation is immediate and reduced motion preserves color cadence`() throws {
    let disabledGraph = ViewGraph()
    try commit(value: 0, property: .opacity, to: disabledGraph, transaction: Transaction(animationTime: .zero))
    try commit(
      value: 1,
      property: .opacity,
      to: disabledGraph,
      transaction: Transaction(
        animation: .linear(duration: .seconds(1)),
        animationsEnabled: false,
        animationTime: .zero
      )
    )
    #expect(disabledGraph.root?.presentationValue(.opacity) == 1)
    #expect(disabledGraph.root?.animationStatus(for: .opacity) == .completed)

    let reducedGraph = ViewGraph()
    try commit(value: 0, property: .opacity, to: reducedGraph, transaction: Transaction(animationTime: .zero))
    try commit(
      value: 1,
      property: .opacity,
      to: reducedGraph,
      transaction: Transaction(
        animation: .linear(duration: .seconds(1)),
        reduceMotion: true,
        animationTime: .zero
      )
    )
    #expect(reducedGraph.root?.presentationValue(.opacity) == 1)
    #expect(reducedGraph.root?.animationStatus(for: .opacity) == .running)

    let spatialGraph = ViewGraph()
    try commit(value: CellVector.zero, property: .offset, to: spatialGraph, transaction: Transaction(animationTime: .zero))
    try commit(
      value: CellVector(x: 4),
      property: .offset,
      to: spatialGraph,
      transaction: Transaction(
        animation: .linear(duration: .seconds(1)),
        reduceMotion: true,
        animationTime: .zero
      )
    )
    #expect(spatialGraph.root?.presentationValue(.offset) == CellVector(x: 4))
    #expect(spatialGraph.root?.animationStatus(for: .offset) == .completed)
  }

  @Test
  func `The string-key animatable value API remains compatible`() throws {
    let property: AnimationPropertyKey = "legacy.amount"
    let graph = ViewGraph()
    try graph.commit(graph.prepare(NodeDescriptor(type: Leaf.self).animatableValue(3.0, for: property)))
    let node = try #require(graph.root)

    #expect(node.presentationValue(for: property, as: Double.self, at: .zero) == 3)
  }

  @Test
  func `Declarative modifiers create typed tracks with their invalidation classes`() throws {
    let firstColor = RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
    let secondColor = RGBA(red: 0.7, green: 0.6, blue: 0.5, alpha: 0.8)
    try expectModifier(.foregroundColor, from: LinearRGBA(firstColor), to: LinearRGBA(secondColor), dirtyFlags: .paint) {
      DescriptorView(Self.leaf).foregroundColor($0.rgba)
    }
    try expectModifier(.backgroundColor, from: LinearRGBA(firstColor), to: LinearRGBA(secondColor), dirtyFlags: .paint) {
      DescriptorView(Self.leaf).backgroundColor($0.rgba)
    }
    try expectModifier(.borderColor, from: LinearRGBA(firstColor), to: LinearRGBA(secondColor), dirtyFlags: .paint) {
      DescriptorView(Self.leaf).borderColor($0.rgba)
    }
    try expectModifier(.opacity, from: -0.25, to: 1.25, dirtyFlags: .paint) {
      DescriptorView(Self.leaf).opacity($0)
    }
    try expectModifier(.offset, from: .zero, to: CellVector(x: 3.5, y: -2.25), dirtyFlags: .layout) {
      DescriptorView(Self.leaf).offset($0)
    }
    try expectModifier(.frameWidth, from: 1.5, to: 8.75, dirtyFlags: .layout) {
      DescriptorView(Self.leaf).animatedFrame(width: $0, height: 4)
    }
    try expectModifier(.frameHeight, from: 2.5, to: 9.25, dirtyFlags: .layout) {
      DescriptorView(Self.leaf).animatedFrame(width: 4, height: $0)
    }
    try expectModifier(.padding, from: .zero, to: Self.insets, dirtyFlags: .layout) {
      DescriptorView(Self.leaf).animatedPadding($0)
    }
    try expectModifier(.spacing, from: 0.5, to: 3.75, dirtyFlags: .layout) {
      DescriptorView(Self.leaf).animatedSpacing($0)
    }
    try expectModifier(.clipInsets, from: .zero, to: Self.insets, dirtyFlags: .layout) {
      DescriptorView(Self.leaf).clipInsets($0)
    }
    try expectModifier(.clipReveal, from: -0.5, to: 1.5, dirtyFlags: .layout) {
      DescriptorView(Self.leaf).reveal($0)
    }
    try expectModifier(.selectionHighlight, from: LinearRGBA(firstColor), to: LinearRGBA(secondColor), dirtyFlags: .paint) {
      DescriptorView(Self.leaf).selectionHighlight($0.rgba)
    }
    try expectModifier(.focusHighlight, from: LinearRGBA(firstColor), to: LinearRGBA(secondColor), dirtyFlags: .paint) {
      DescriptorView(Self.leaf).focusHighlight($0.rgba)
    }
    try expectModifier(.scrollPosition, from: .zero, to: CellVector(x: 12.5, y: 6.25), dirtyFlags: .layout) {
      DescriptorView(Self.leaf).scrollPosition($0)
    }
  }

  @Test
  func `Coordinate convenience overloads retain floating targets`() throws {
    try expectModifier(.offset, from: .zero, to: CellVector(x: 2.5, y: -1.5), dirtyFlags: .layout) {
      DescriptorView(Self.leaf).offset(x: $0.x, y: $0.y)
    }
    try expectModifier(.scrollPosition, from: .zero, to: CellVector(x: -3.5, y: 7.5), dirtyFlags: .layout) {
      DescriptorView(Self.leaf).scrollPosition(x: $0.x, y: $0.y)
    }
  }

  @Test
  func `A modifier preserves the expanded descriptor identity and evaluates its body once`() throws {
    var evaluationCount = 0
    let descriptor = NodeDescriptor(type: Leaf.self, key: "stable")
    let view = EvaluatedDescriptorView(descriptor: descriptor) {
      evaluationCount += 1
    }
    let graph = ViewGraph()

    try commit(view.opacity(0.5), to: graph)
    let contentNode = try #require(graph.root?.children.first)

    #expect(contentNode.identity == StructuralIdentity(type: EvaluatedDescriptorView.self))
    #expect(contentNode.children.first?.identity == descriptor.identity)
    #expect(evaluationCount == 1)
    #expect(contentNode.presentationValue(.opacity) == 0.5)
  }

  @Test
  func `Transition sampling invalidates layout only for resolved spatial effects`() throws {
    try expectTransitionDirtyFlags(.opacity, expected: .paint)
    try expectTransitionDirtyFlags(.symbolFrames(SymbolFrames(["a", "b"])), expected: .paint)
    try expectTransitionDirtyFlags(.move(edge: .leading), expected: .layout)
    try expectTransitionDirtyFlags(.reveal(edge: .bottom), expected: .layout)
    try expectTransitionDirtyFlags(.wipe(edge: .trailing), expected: .layout)
  }

  @Test
  func `Transition samples retain reveal and wipe edges`() {
    let transition = AnyTransition.reveal(edge: .bottom).combined(with: .wipe(edge: .trailing))
    let sample = transition.sample(phase: .insertion, progress: 0.5)

    #expect(sample.revealEdge == .bottom)
    #expect(sample.revealFraction == 0.5)
    #expect(sample.wipeEdge == .trailing)
    #expect(sample.wipeFraction == 0.5)
  }

  private func expect(
    _ property: PresentationProperty<some Any>,
    key: AnimationPropertyKey,
    dirtyFlags: DirtyFlags
  ) {
    #expect(property.key == key)
    #expect(property.dirtyFlags == dirtyFlags)
  }

  private static var leaf: NodeDescriptor {
    NodeDescriptor(type: Leaf.self)
  }

  private static var insets: FloatingEdgeInsets {
    FloatingEdgeInsets(top: 0.5, leading: 1.25, bottom: 2.5, trailing: 3.75)
  }

  private func expectModifier<Value: VectorArithmetic & Hashable>(
    _ property: PresentationProperty<Value>,
    from initialValue: Value,
    to targetValue: Value,
    dirtyFlags: DirtyFlags,
    content: (Value) -> some View
  ) throws {
    let graph = ViewGraph()
    try commit(content(initialValue).animation(.linear(duration: .seconds(1)), value: initialValue), to: graph)
    try commit(content(targetValue).animation(.linear(duration: .seconds(1)), value: targetValue), to: graph)
    let node = try #require(firstNode(in: graph.root, with: property))

    #expect(node.presentationValue(property) == targetValue)
    #expect(node.animationStatus(for: property) == .running)
    graph.clearDirtyFlags()
    #expect(graph.sampleMountedAttributes(at: .zero.advanced(by: .milliseconds(500))) == 1)
    #expect(node.dirtyFlags == dirtyFlags)
  }

  private func expectTransitionDirtyFlags(_ transition: AnyTransition, expected: DirtyFlags) throws {
    let graph = ViewGraph()
    let transaction = Transaction(animation: .linear(duration: .seconds(1)), animationTime: .zero)
    try withTransaction(transaction) {
      try graph.commit(graph.prepare(NodeDescriptor(type: Leaf.self).transition(transition)))
    }
    graph.clearDirtyFlags()

    #expect(graph.sampleMountedAttributes(at: .zero.advanced(by: .milliseconds(500))) == 1)
    #expect(graph.root?.dirtyFlags == expected)
  }

  private func commit(_ content: some View, to graph: ViewGraph) throws {
    try withTransaction(Transaction(animationTime: .zero)) {
      try graph.commit(graph.prepare(content))
    }
  }

  private func firstNode(
    in node: MountedNode?,
    with property: PresentationProperty<some VectorArithmetic>
  ) -> MountedNode? {
    guard let node else { return nil }
    if node.presentationValue(property) != nil {
      return node
    }
    for child in node.children {
      if let match = firstNode(in: child, with: property) {
        return match
      }
    }
    return nil
  }

  private func commit<Value: VectorArithmetic>(
    value: Value,
    property: PresentationProperty<Value>,
    to graph: ViewGraph,
    transaction: Transaction
  ) throws {
    try withTransaction(transaction) {
      try graph.commit(graph.prepare(NodeDescriptor(type: Leaf.self).presentationValue(value, for: property)))
    }
  }

  private func commitChild(
    offset: CellVector,
    opacity: Double,
    to graph: ViewGraph,
    transaction: Transaction
  ) throws {
    try withTransaction(transaction) {
      let child = NodeDescriptor(type: Leaf.self)
        .presentationValue(offset, for: .offset)
        .presentationValue(opacity, for: .opacity)
      try graph.commit(graph.prepare(NodeDescriptor(type: Root.self, children: [child])))
    }
  }
}

@MainActor
private struct EvaluatedDescriptorView: View {
  let descriptor: NodeDescriptor
  let onEvaluation: () -> Void

  var graphBody: [NodeDescriptor] {
    onEvaluation()
    [descriptor]
  }
}
