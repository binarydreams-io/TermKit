@MainActor
protocol DeclarativeSemanticActionRuntimeView: AnyObject {
  func performSemanticAction(_ action: SemanticAction, on id: SemanticID) -> Bool
}

private struct RuntimeOverlayLayoutPrimitive: Sendable, Hashable {}

private struct RuntimeOverlayItemPrimitive: Sendable, Hashable {
  var kind: OverlayKind
}

@MainActor
final class DeclarativeRuntimeView<Root: View>: IncrementalRuntimeView, DeclarativeSemanticActionRuntimeView {
  struct Counters: Equatable {
    var layoutPassCount = 0
    var measurementCount = 0
    var paintVisitCount = 0
    var offscreenLayerCount = 0
    var offscreenCellCount = 0
  }

  private struct Presentation {
    var foreground: LinearRGBA?
    var background: LinearRGBA?
    var border: LinearRGBA?
    var opacity: Double?
    var offset: CellVector?
    var frameWidth: Double?
    var frameHeight: Double?
    var padding: FloatingEdgeInsets?
    var spacing: Double?
    var clipInsets: FloatingEdgeInsets?
    var reveal: Double?
    var selectionHighlight: LinearRGBA?
    var focusHighlight: LinearRGBA?
    var scrollPosition: CellVector?
    var transition: TransitionSample?
    var isAnimating = false
  }

  private let root: Root
  private let overlayHost: ViewOverlayHost?
  private let layoutCache = LayoutCache()
  private weak var graph: ViewGraph?
  private var clips: [NodeID: CellRect] = [:]
  private var presentations: [NodeID: Presentation] = [:]
  private var focusedNodeID: NodeID?
  private var activeModalScopes: [String] = []
  private var focusRestoration: [String: NodeID?] = [:]
  private var retainedFrames: [NodeID: CellRect] = [:]
  private var previousAnimatedBounds: [NodeID: CellRect] = [:]
  private var layoutProposals: [NodeID: ProposedCellSize] = [:]
  private var usesReducedMotion = false
  private var incrementalSnapshot: IncrementalSnapshot?
  private var retainedSurface: Surface?
  private var retainedSemantics: [NodeID: [SemanticNode]] = [:]
  private var retainedPaintBounds: [NodeID: CellRect] = [:]
  private var incrementalDirtyBounds: [(old: CellRect, node: MountedNode)] = []
  private var incrementalDirtyNodes: [MountedNode] = []
  private var sceneChildCache: [NodeID: [MountedNode]] = [:]
  private var sceneRowIndex: [Int: [MountedNode]] = [:]
  private var paintContributorIDs: Set<NodeID>?
  private var paintChildCache: [NodeID: [MountedNode]] = [:]
  private var externalDamage: DamageTracker?
  private var rebuildSemanticAncestors = false
  private var requiresFullPaint = false
  private(set) var counters = Counters()

  var incrementalCounters: IncrementalRuntimeCounters {
    IncrementalRuntimeCounters(
      layoutPassCount: counters.layoutPassCount,
      measurementCount: counters.measurementCount,
      paintVisitCount: counters.paintVisitCount,
      offscreenLayerCount: counters.offscreenLayerCount,
      offscreenCellCount: counters.offscreenCellCount
    )
  }

  var activePresentationNodes: [MountedNode] {
    presentations.compactMap { id, presentation in
      guard presentation.isAnimating else { return nil }
      return graph?.node(withID: id) ?? graph?.presentationNode(withID: id)
    }
  }

  private struct IncrementalSnapshot {
    let clips: [NodeID: CellRect]
    let presentations: [NodeID: Presentation]
    let retainedFrames: [NodeID: CellRect]
    let previousAnimatedBounds: [NodeID: CellRect]
    let layoutProposals: [NodeID: ProposedCellSize]
    let retainedSurface: Surface?
    let retainedSemantics: [NodeID: [SemanticNode]]
    let retainedPaintBounds: [NodeID: CellRect]
    let requiresFullPaint: Bool
  }

  init(root: Root, overlayHost: ViewOverlayHost? = nil) {
    self.root = root
    self.overlayHost = overlayHost
  }

  func nodeDescriptor(in context: RuntimeFrameContext) -> NodeDescriptor {
    usesReducedMotion = context.motionPolicy == .reduced
    let descriptor: NodeDescriptor
    if let overlayHost {
      var rootDescriptor = NodeDescriptor.makeDeclarative(root).atIndex(0)
      rootDescriptor.hitTest.zIndex = Int.min
      var children = [rootDescriptor]
      children.append(contentsOf: overlayHost.orderedOverlays.map { overlay in
        NodeDescriptor(
          type: RuntimeOverlayItemPrimitive.self,
          key: overlay.id,
          primitive: RuntimeOverlayItemPrimitive(kind: overlay.kind),
          children: [NodeDescriptor.makeDeclarative(overlay.content)],
          hitTest: HitTestMetadata(
            disablesDescendants: false,
            zIndex: overlay.zIndex,
            modalScope: overlay.isModal ? overlay.id.rawValue : nil
          ),
          dirtyOnUpdate: .layout
        )
      })
      descriptor = NodeDescriptor(
        type: RuntimeOverlayLayoutPrimitive.self,
        primitive: RuntimeOverlayLayoutPrimitive(),
        children: children,
        dirtyOnUpdate: .layout
      )
    } else {
      descriptor = NodeDescriptor.makeDeclarative(root)
    }
    return descriptor.scopedExpansion { _, body in
      try withTransaction(context.transaction, body)
    }
  }

  func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws {
    self.graph = graph
    counters.layoutPassCount += 1
    layoutCache.removeAll()
    layoutProposals.removeAll(keepingCapacity: true)
    clips.removeAll(keepingCapacity: true)
    presentations.removeAll(keepingCapacity: true)
    try sampleAndLayout(in: context, graph: graph)
  }

  func beginIncrementalFrame(
    in context: RuntimeFrameContext,
    graph: ViewGraph,
    dirtyNodes: [ViewGraphFrame.DirtyNode],
    externalDamage: DamageTracker
  ) {
    self.graph = graph
    incrementalSnapshot = IncrementalSnapshot(
      clips: clips,
      presentations: presentations,
      retainedFrames: retainedFrames,
      previousAnimatedBounds: previousAnimatedBounds,
      layoutProposals: layoutProposals,
      retainedSurface: retainedSurface,
      retainedSemantics: retainedSemantics,
      retainedPaintBounds: retainedPaintBounds,
      requiresFullPaint: requiresFullPaint
    )
    incrementalDirtyBounds = dirtyNodes.filter { $0.localDirtyFlags.isEmpty == false }.map {
      ($0.oldPaintBounds, $0.node)
    }
    incrementalDirtyNodes = dirtyNodes.filter { $0.localDirtyFlags.isEmpty == false }.map(\.node)
    self.externalDamage = externalDamage
    rebuildSemanticAncestors = externalDamage.isEmpty == false
  }

  func updatePresentation(in context: RuntimeFrameContext, graph: ViewGraph, layout: Bool) throws {
    if layout {
      rebuildSemanticAncestors = true
      counters.layoutPassCount += 1
      try sampleAndLayout(in: context, graph: graph)
    } else if rebuildSemanticAncestors {
      if let root = graph.root {
        try samplePresentation(in: root, context: context)
      }
      for root in graph.presentationRoots {
        try samplePresentation(in: root, context: context)
      }
    } else {
      for node in incrementalDirtyNodes {
        try samplePresentationValue(in: node, context: context)
      }
    }
  }

  func finishIncrementalFrame() {
    incrementalSnapshot = nil
    incrementalDirtyBounds.removeAll(keepingCapacity: true)
    incrementalDirtyNodes.removeAll(keepingCapacity: true)
    externalDamage = nil
    rebuildSemanticAncestors = false
  }

  func rollbackIncrementalFrame() {
    guard let snapshot = incrementalSnapshot else { return }
    clips = snapshot.clips
    presentations = snapshot.presentations
    retainedFrames = snapshot.retainedFrames
    previousAnimatedBounds = snapshot.previousAnimatedBounds
    layoutProposals = snapshot.layoutProposals
    retainedSurface = snapshot.retainedSurface
    retainedSemantics = snapshot.retainedSemantics
    retainedPaintBounds = snapshot.retainedPaintBounds
    requiresFullPaint = snapshot.requiresFullPaint
    incrementalSnapshot = nil
    incrementalDirtyBounds.removeAll(keepingCapacity: true)
    incrementalDirtyNodes.removeAll(keepingCapacity: true)
    externalDamage = nil
    rebuildSemanticAncestors = false
  }

  private func sampleAndLayout(in context: RuntimeFrameContext, graph: ViewGraph) throws {
    let bounds = CellRect(origin: .zero, size: context.terminalSize)
    if let root = graph.root {
      try samplePresentation(in: root, context: context)
      if usesReducedMotion {
        applyReducedTargets(in: root)
      }
      forwardLayoutPresentation(in: root)
      _ = place(
        root,
        proposal: ProposedCellSize(width: context.terminalSize.width, height: context.terminalSize.height),
        origin: .zero,
        clip: bounds,
        inheritedOffset: .zero
      )
    }
    let retainedIDs = Set(graph.presentationRoots.map(\.id))
    retainedFrames = retainedFrames.filter { retainedIDs.contains($0.key) }
    for root in graph.presentationRoots {
      try samplePresentation(in: root, context: context)
      guard let cached = retainedFrames[root.id] ?? root.cachedFrame else { continue }
      retainedFrames[root.id] = cached
      let presentation = presentations[root.id] ?? Presentation()
      let transitionOffset = presentation.transition?.offset ?? .zero
      let offset = CellPoint(
        x: quantize((presentation.offset?.x ?? 0) + transitionOffset.first),
        y: quantize((presentation.offset?.y ?? 0) + transitionOffset.second)
      )
      let frame = cached.offsetBy(dx: offset.x, dy: offset.y)
      let clip = finalClip(for: root, frame: frame, inherited: bounds)
      root.cache(size: frame.size, frame: frame, paintBounds: clip)
      clips[root.id] = clip
      updateDescendantFrames(of: root, dx: frame.minX - cached.minX, dy: frame.minY - cached.minY, clip: clip)
    }
    if focusedNodeID.map({ graph.node(withID: $0)?.isFocusable != true }) ?? false {
      focusedNodeID = nil
    }
    rebuildSceneChildCache(graph: graph)
    synchronizeModalFocus(in: graph)
  }

  func paint(
    in context: RuntimeFrameContext,
    resources: inout ControlRenderResources
  ) throws -> RuntimeFrame {
    let frameBounds = CellRect(origin: .zero, size: context.terminalSize)
    let canIncrement =
      retainedSurface?.size == context.terminalSize
        && hasStructuralInvalidation(in: graph?.root) == false
        && externalDamage?.isEmpty != false
        && requiresFullPaint == false
    var surface =
      canIncrement
        ? retainedSurface ?? Surface(size: context.terminalSize)
        : Surface(size: context.terminalSize)
    var paintDamage = DamageTracker(bounds: frameBounds)
    if canIncrement {
      for dirty in incrementalDirtyBounds {
        paintDamage.add(dirty.old)
        paintDamage.add(dirty.node.paintBounds)
      }
      for (id, presentation) in presentations where presentation.isAnimating {
        if let node = graph?.node(withID: id) ?? graph?.presentationNode(withID: id) {
          paintDamage.add(node.paintBounds)
        }
      }
      paintDamage.add(contentsOf: previousAnimatedBounds.values)
      paintDamage.add(contentsOf: externalDamage?.rectangles ?? [])
      var expanded = DamageTracker(bounds: frameBounds)
      for rect in paintDamage.rectangles {
        let old = retainedSurface?.atomExpanded(rect) ?? rect
        expanded.add(surface.atomExpanded(old))
      }
      paintDamage = expanded
      for rect in paintDamage.rectangles {
        surface.clear(rect)
      }
    } else {
      paintDamage.invalidateAll()
      retainedSemantics.removeAll(keepingCapacity: true)
    }
    let paintClip = canIncrement ? paintDamage : nil
    if let paintClip {
      let contributors = contributors(to: paintClip)
      paintContributorIDs = contributors.ids
      paintChildCache = contributors.children
    }
    defer {
      paintContributorIDs = nil
      paintChildCache.removeAll(keepingCapacity: true)
    }
    if let root = graph?.root {
      let semantics = try paintNode(root, into: &surface, damage: paintClip, resources: &resources)
      if semantics.isEmpty == false, paintClip == nil || rebuildSemanticAncestors {
        retainedSemantics[root.id] = semantics
      }
    }
    for root in scenePresentationRoots(parentID: nil) where root.cachedFrame != nil {
      _ = try paintNode(root, into: &surface, damage: paintClip, resources: &resources)
    }
    if canIncrement {
      var expanded = DamageTracker(bounds: frameBounds)
      for rect in paintDamage.rectangles {
        expanded.add(surface.atomExpanded(rect))
      }
      paintDamage = expanded
    }
    let semanticRoots = graph?.root.flatMap { retainedSemantics[$0.id] } ?? []

    let bounds = surface.bounds
    var damage = DamageTracker(bounds: bounds)
    var currentAnimatedBounds: [NodeID: CellRect] = [:]
    for (id, presentation) in presentations where presentation.isAnimating {
      if let node = graph?.node(withID: id) ?? graph?.presentationNode(withID: id) {
        currentAnimatedBounds[id] = node.paintBounds
        damage.add(node.paintBounds)
      }
    }
    for rect in previousAnimatedBounds.values {
      damage.add(rect)
    }
    let hasLocalizedDamage = previousAnimatedBounds.isEmpty == false || currentAnimatedBounds.isEmpty == false
    previousAnimatedBounds = currentAnimatedBounds
    retainedSurface = surface
    requiresFullPaint = false
    return RuntimeFrame(
      surface: surface,
      semantics: SemanticTree(roots: semanticRoots),
      damage: hasLocalizedDamage ? damage : (canIncrement ? paintDamage : nil)
    )
  }

  func dispatch(_ event: TerminalInputEvent) {
    guard let graph else { return }
    switch event {
    case let .key(key) where key.action != .release && key.key == .escape:
      if overlayHost?.handleEscape() == true {
        return
      }
      guard let focusedNodeID, let node = graph.node(withID: focusedNodeID) else { return }
      _ = dispatch(key, to: node)
    case let .key(key) where key.action != .release && key.key == .tab:
      if let focusedNodeID,
         let node = graph.node(withID: focusedNodeID),
         node.primitive(as: (any ControlFocusTrapping).self)?.trapsControlFocus == true
      {
        return
      }
      moveFocus(backward: key.modifiers.contains(.shift), in: graph)
    case let .key(key) where key.action != .release:
      guard let focusedNodeID, let node = graph.node(withID: focusedNodeID) else { return }
      let modalScope = graph.root.flatMap(topmostModalScope)
      guard modalScope == nil || node.activeModalScope == modalScope else { return }
      if dispatchShortcut(key, to: node) == false,
         dispatch(key, to: node) == false,
         key.key == .enter
      {
        activate(node)
      }
    case let .paste(text):
      dispatch(.paste(text), toFocusedNodeIn: graph)
    case let .mouse(mouse):
      guard case .release(.some(.left)) = mouse.action else { return }
      let point = CellPoint(x: mouse.position.column, y: mouse.position.row)
      guard let root = graph.root, let node = presentedHitTest(point, in: root) else { return }
      if node.isFocusable {
        setFocusedNodeID(node.id, in: graph)
      }
      let localPoint = node.cachedFrame.map { point.offsetBy(dx: -$0.minX, dy: -$0.minY) } ?? point
      if node.primitive(as: (any ControlPointerActivatable).self)?.activate(at: localPoint) == true {
        node.invalidate(.paint)
      } else {
        activate(node)
      }
    default:
      break
    }
  }

  func performSemanticAction(_ action: SemanticAction, on id: SemanticID) -> Bool {
    guard let frame = semanticFrame(for: id), let graph else { return false }
    var pending = graph.presentationRoots
    if let root = graph.root {
      pending.append(root)
    }
    var nodes: [MountedNode] = []
    while let node = pending.popLast() {
      nodes.append(node)
      pending.append(contentsOf: node.children)
    }
    for node in nodes.reversed() where node.cachedFrame?.intersects(frame) == true {
      if node.primitive(as: (any ControlSemanticActionHandler).self)?.handleSemanticAction(action) == true {
        node.invalidate(.layout)
        return true
      }
    }
    return false
  }

  private func semanticFrame(for id: SemanticID) -> CellRect? {
    retainedSemantics.values.lazy.flatMap(\.self).compactMap { $0.node(withID: id)?.frame }.first
  }

  private func dispatch(_ key: TerminalKeyEvent, to node: MountedNode) -> Bool {
    let event: ControlInputEvent?
    switch key.key {
    case let .text(text):
      let commandModifiers: TerminalKeyModifiers = [.control, .super, .hyper, .meta]
      event = key.modifiers.isDisjoint(with: commandModifiers) ? .text(text) : nil
    case .enter:
      event = key.modifiers.isEmpty ? .submit : .newline
    case .escape:
      event = .cancel
    case .up:
      event = .moveUp
    case .down:
      event = .moveDown
    case .left:
      event = key.modifiers.contains(.shift) ? nil : .moveLeft
    case .right:
      event = key.modifiers.contains(.shift) ? nil : .moveRight
    case .backspace:
      event = .deleteBackward
    default:
      event = nil
    }
    guard let event else { return false }
    let handled = node.primitive(as: (any ControlInputHandler).self)?.handleControlInput(event) ?? false
    if handled {
      node.invalidate(.paint)
    }
    return handled
  }

  private func dispatchShortcut(_ key: TerminalKeyEvent, to node: MountedNode) -> Bool {
    guard let shortcut = key.keyboardShortcut,
          let handler = node.primitive(as: (any ControlShortcutHandler).self)
    else { return false }
    let handled = handler.handleKeyboardShortcut(shortcut)
    if handled {
      node.invalidate(.paint)
    }
    return handled
  }

  private func dispatch(_ event: ControlInputEvent, toFocusedNodeIn graph: ViewGraph) {
    guard let focusedNodeID, let node = graph.node(withID: focusedNodeID) else { return }
    node.primitive(as: (any ControlInputHandler).self)?.handleControlInput(event)
  }

  private func samplePresentation(in node: MountedNode, context: RuntimeFrameContext) throws {
    try samplePresentationValue(in: node, context: context)
    for child in node.children {
      try samplePresentation(in: child, context: context)
    }
  }

  private func samplePresentationValue(in node: MountedNode, context: RuntimeFrameContext) throws {
    func value<Value: VectorArithmetic>(_ property: PresentationProperty<Value>) throws -> Value? {
      let value =
        usesReducedMotion
          ? node.presentationTarget(for: property)
          : node.presentationValue(property, at: context.instant) ?? node.presentationTarget(for: property)
      guard let value else { return nil }
      guard presentationValueIsFinite(value) else {
        throw RuntimeError.invalidPresentationValue(
          property: property.key,
          value: String(describing: value)
        )
      }
      return value
    }
    func running(_ property: PresentationProperty<some VectorArithmetic>) -> Bool {
      node.animationStatus(for: property) == .running
    }
    var presentation = Presentation()
    presentation.foreground = try value(.foregroundColor)
    presentation.background = try value(.backgroundColor)
    presentation.border = try value(.borderColor)
    presentation.opacity = try value(.opacity)
    presentation.offset = try value(.offset)
    presentation.frameWidth = try value(.frameWidth)
    presentation.frameHeight = try value(.frameHeight)
    presentation.padding = try value(.padding)
    presentation.spacing = try value(.spacing)
    presentation.clipInsets = try value(.clipInsets)
    presentation.reveal = try value(.clipReveal)
    presentation.selectionHighlight = try value(.selectionHighlight)
    presentation.focusHighlight = try value(.focusHighlight)
    presentation.scrollPosition = try value(.scrollPosition)
    presentation.transition = context.motionPolicy == .reduced ? nil : node.transitionPresentationSample(at: context.instant)
    presentation.isAnimating =
      running(.foregroundColor) || running(.backgroundColor)
        || running(.borderColor) || running(.opacity) || running(.offset)
        || running(.frameWidth) || running(.frameHeight) || running(.padding)
        || running(.spacing) || running(.clipInsets) || running(.clipReveal)
        || running(.selectionHighlight) || running(.focusHighlight)
        || running(.scrollPosition) || node.presentationPhase != .active
    presentations[node.id] = presentation
  }

  private func forwardLayoutPresentation(in node: MountedNode?) {
    guard let node else { return }
    for child in node.children {
      forwardLayoutPresentation(in: child)
    }
    guard node.primitive(as: LayoutPrimitive.self) == nil,
          let child = firstLayoutPrimitive(in: node.children.first)
    else { return }
    var source = presentations[node.id] ?? Presentation()
    var destination = presentations[child.id] ?? Presentation()
    destination.frameWidth = destination.frameWidth ?? source.frameWidth
    destination.frameHeight = destination.frameHeight ?? source.frameHeight
    destination.padding = destination.padding ?? source.padding
    destination.spacing = destination.spacing ?? source.spacing
    destination.scrollPosition = destination.scrollPosition ?? source.scrollPosition
    source.frameWidth = nil
    source.frameHeight = nil
    source.padding = nil
    source.spacing = nil
    source.scrollPosition = nil
    presentations[node.id] = source
    presentations[child.id] = destination
  }

  private func applyReducedTargets(in node: MountedNode) {
    var presentation = presentations[node.id] ?? Presentation()
    presentation.offset = node.presentationTarget(for: PresentationProperties.offset) ?? presentation.offset
    presentations[node.id] = presentation
    for child in node.children {
      applyReducedTargets(in: child)
    }
  }

  private func firstLayoutPrimitive(in node: MountedNode?) -> MountedNode? {
    guard let node else { return nil }
    if node.primitive(as: LayoutPrimitive.self) != nil {
      return node
    }
    guard node.children.count == 1 else { return nil }
    return firstLayoutPrimitive(in: node.children.first)
  }

  private func measure(_ node: MountedNode, proposal: ProposedCellSize) -> CellSize {
    counters.measurementCount += 1
    if let renderable = node.primitive(as: (any SemanticRenderable).self) {
      return renderable.sizeThatFits(proposal)
    }
    return layoutResult(for: node, proposal: proposal).size
  }

  private func layoutResult(for node: MountedNode, proposal: ProposedCellSize) -> LayoutResult {
    let items = node.children.map { child in
      LayoutItem(node: child) { [self] childProposal in measure(child, proposal: childProposal) }
    }
    if node.primitive(as: RuntimeOverlayLayoutPrimitive.self) != nil {
      let sizes = items.map { layoutCache.measure($0, in: proposal) }
      let natural = CellSize(
        width: sizes.map(\.width).max() ?? 0,
        height: sizes.map(\.height).max() ?? 0
      )
      let container = proposal.replacingUnspecifiedDimensions(by: natural)
      let placements = zip(zip(node.children, items), sizes).map { pair, size in
        let (child, item) = pair
        guard let overlay = child.primitive(as: RuntimeOverlayItemPrimitive.self) else {
          return LayoutPlacement(
            nodeID: item.nodeID,
            frame: CellRect(origin: .zero, size: container)
          )
        }
        let origin = switch overlay.kind {
        case .toast:
          CellPoint(
            x: max(0, container.width - size.width - 1),
            y: min(1, max(0, container.height - size.height))
          )
        case .dialog, .menu, .custom:
          CellPoint(
            x: max(0, (container.width - size.width) / 2),
            y: max(0, (container.height - size.height) / 2)
          )
        }
        return LayoutPlacement(
          nodeID: item.nodeID,
          frame: CellRect(origin: origin, size: size)
        )
      }
      return LayoutResult(size: container, placements: placements)
    }
    guard let primitive = node.primitive(as: LayoutPrimitive.self) else {
      let sizes = items.map { layoutCache.measure($0, in: proposal) }
      let natural = CellSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
      return LayoutResult(
        size: natural,
        placements: zip(items, sizes).map {
          LayoutPlacement(nodeID: $0.nodeID, frame: CellRect(origin: .zero, size: $1))
        }
      )
    }
    let presentation = presentations[node.id] ?? Presentation()
    switch primitive {
    case var .stack(layout):
      if let spacing = presentation.spacing {
        layout.spacing = nonnegative(spacing)
      }
      return layout.layout(items, in: proposal, cache: layoutCache)
    case var .padding(layout):
      guard let item = items.first else { return LayoutResult(size: .zero, placements: []) }
      if let padding = presentation.padding {
        layout.insets = edgeInsets(padding)
      }
      return layout.layout(item, in: proposal, cache: layoutCache)
    case var .frame(layout):
      guard let item = items.first else { return LayoutResult(size: .zero, placements: []) }
      if let width = presentation.frameWidth {
        layout.width = nonnegative(width)
      }
      if let height = presentation.frameHeight {
        layout.height = nonnegative(height)
      }
      return layout.layout(item, in: proposal, cache: layoutCache)
    case let .scrollViewport(layout):
      guard let item = items.first else { return LayoutResult(size: .zero, placements: []) }
      let viewport = CellSize(
        width: layout.width ?? proposal.width ?? layoutCache.measure(item, in: .unspecified).width,
        height: layout.height ?? proposal.height ?? layoutCache.measure(item, in: .unspecified).height
      )
      let content = layoutCache.measure(item, in: .unspecified)
      let scroll = presentation.scrollPosition ?? .zero
      let origin = CellPoint(x: -nonnegative(scroll.x), y: -nonnegative(scroll.y))
      return LayoutResult(
        size: viewport,
        placements: [
          LayoutPlacement(
            nodeID: item.nodeID,
            frame: CellRect(origin: origin, size: content),
            clip: CellRect(origin: .zero, size: viewport)
          )
        ]
      )
    }
  }

  @discardableResult
  private func place(
    _ node: MountedNode,
    proposal: ProposedCellSize,
    origin: CellPoint,
    clip: CellRect,
    inheritedOffset: CellVector
  ) -> CellSize {
    let presentation = presentations[node.id] ?? Presentation()
    let transitionOffset = presentation.transition?.offset ?? .zero
    let offsetValue =
      presentation.offset
        ?? (usesReducedMotion ? node.presentationTarget(for: PresentationProperties.offset) : nil)
    let accumulatedOffset = CellVector(
      x: inheritedOffset.x + (offsetValue?.x ?? 0) + transitionOffset.first,
      y: inheritedOffset.y + (offsetValue?.y ?? 0) + transitionOffset.second
    )
    let presentedOrigin = origin.offsetBy(dx: quantize(accumulatedOffset.x), dy: quantize(accumulatedOffset.y))
    if node.dirtyFlags.contains(.layout) == false,
       layoutProposals[node.id] == proposal,
       let previousFrame = node.cachedFrame,
       let size = node.cachedSize
    {
      let dx = presentedOrigin.x - previousFrame.minX
      let dy = presentedOrigin.y - previousFrame.minY
      let frame = previousFrame.offsetBy(dx: dx, dy: dy)
      let visible = finalClip(for: node, frame: frame, inherited: clip)
      node.cache(size: size, frame: frame, paintBounds: visible)
      clips[node.id] = visible
      updateDescendantFrames(of: node, dx: dx, dy: dy, clip: visible)
      return size
    }
    layoutProposals[node.id] = proposal
    if node.primitive(as: (any SemanticRenderable).self) != nil {
      let size = measure(node, proposal: proposal)
      let frame = CellRect(origin: presentedOrigin, size: size)
      let visible = finalClip(for: node, frame: frame, inherited: clip)
      node.cache(size: size, frame: frame, paintBounds: visible)
      clips[node.id] = visible
      return size
    }

    let result = layoutResult(for: node, proposal: proposal)
    let frame = CellRect(origin: presentedOrigin, size: result.size)
    let nodeClip = finalClip(for: node, frame: frame, inherited: clip)
    node.cache(size: result.size, frame: frame, paintBounds: nodeClip)
    clips[node.id] = nodeClip
    let childrenByID = Dictionary(uniqueKeysWithValues: node.children.map { ($0.id, $0) })
    for placement in result.placements {
      guard let child = childrenByID[placement.nodeID] else { continue }
      let childOrigin = origin.offsetBy(dx: placement.frame.minX, dy: placement.frame.minY)
      var childClip = clip
      if let placementClip = placement.clip {
        let absoluteClip = placementClip.offsetBy(dx: presentedOrigin.x, dy: presentedOrigin.y)
        childClip = childClip.intersection(absoluteClip) ?? .zero
      }
      _ = place(
        child,
        proposal: ProposedCellSize(width: placement.frame.width, height: placement.frame.height),
        origin: childOrigin,
        clip: childClip,
        inheritedOffset: accumulatedOffset
      )
    }
    let subtreeBounds = node.children.reduce(nodeClip) { bounds, child in
      bounds.union(child.paintBounds)
    }
    let paintBounds = clip.intersection(subtreeBounds) ?? .zero
    node.cache(size: result.size, frame: frame, paintBounds: paintBounds)
    clips[node.id] = paintBounds
    return result.size
  }

  private func finalClip(for node: MountedNode, frame: CellRect, inherited: CellRect) -> CellRect {
    let presentation = presentations[node.id] ?? Presentation()
    var clip = inherited.intersection(frame) ?? .zero
    if let insets = presentation.clipInsets {
      clip = clip.inset(by: edgeInsets(insets))
    }
    if let reveal = presentation.reveal {
      clip = revealedClip(clip, in: frame, fraction: reveal, edge: .leading)
    }
    if let transition = presentation.transition {
      if let edge = transition.revealEdge {
        clip = revealedClip(clip, in: frame, fraction: transition.revealFraction, edge: edge)
      }
      if let edge = transition.wipeEdge {
        clip = revealedClip(clip, in: frame, fraction: transition.wipeFraction, edge: edge)
      }
    }
    return clip
  }

  private func revealedClip(
    _ clip: CellRect,
    in frame: CellRect,
    fraction: Double,
    edge: TransitionEdge
  ) -> CellRect {
    let fraction = min(1, max(0, fraction))
    let revealed: CellRect
    switch edge {
    case .top, .bottom:
      let height = max(0, Int((Double(frame.height) * fraction).rounded(.up)))
      let y = edge == .bottom ? frame.maxY - height : frame.minY
      revealed = CellRect(x: frame.minX, y: y, width: frame.width, height: height)
    case .leading, .trailing:
      let width = max(0, Int((Double(frame.width) * fraction).rounded(.up)))
      let x = edge == .trailing ? frame.maxX - width : frame.minX
      revealed = CellRect(x: x, y: frame.minY, width: width, height: frame.height)
    }
    return clip.intersection(revealed) ?? .zero
  }

  private func updateDescendantFrames(of node: MountedNode, dx: Int, dy: Int, clip: CellRect) {
    for child in node.children {
      if let frame = child.cachedFrame?.offsetBy(dx: dx, dy: dy) {
        let visible = clip.intersection(frame) ?? .zero
        child.cache(size: frame.size, frame: frame, paintBounds: visible)
        clips[child.id] = visible
      }
      updateDescendantFrames(of: child, dx: dx, dy: dy, clip: clip)
    }
  }

  private func paintNode(
    _ node: MountedNode,
    into destination: inout Surface,
    damage: DamageTracker?,
    resources: inout ControlRenderResources
  ) throws -> [SemanticNode] {
    if let damage, contributes(node, to: damage) == false {
      return retainedSemantics[node.id] ?? []
    }
    counters.paintVisitCount += 1
    retainedPaintBounds[node.id] = node.paintBounds
    let presentation = presentations[node.id] ?? Presentation()
    let opacity = min(1, max(0, (presentation.opacity ?? 1) * (presentation.transition?.opacity ?? 1)))
    let focusHighlight = presentation.focusHighlight ?? node.presentationTarget(for: PresentationProperties.focusHighlight)
    let selectionHighlight =
      presentation.selectionHighlight
        ?? node.presentationTarget(for: PresentationProperties.selectionHighlight)
    let isolates =
      opacity < 1 || presentation.transition?.symbol != nil
        || focusHighlight != nil || selectionHighlight != nil
    let previousPaintStyle = resources.paintStyle
    let foreground = presentation.foreground.map { Color.rgba($0.rgba) }
    let backgroundOverride = presentation.background.map { Color.rgba($0.rgba) }
    resources.paintStyle = previousPaintStyle.overriding(foreground: foreground, background: backgroundOverride)
    defer { resources.paintStyle = previousPaintStyle }

    let semantics: [SemanticNode]
    if isolates {
      var layer = Surface(
        bounds: node.paintBounds.intersection(destination.bounds) ?? .zero,
        fill: .transparent
      )
      counters.offscreenLayerCount += 1
      counters.offscreenCellCount += layer.size.cellCount
      semantics = try paintSubtree(
        node,
        into: &layer,
        damage: damage,
        focusHighlight: focusHighlight,
        selectionHighlight: selectionHighlight,
        resources: &resources
      )
      try destination.composite(
        layer,
        clip: node.paintBounds,
        opacity: opacity,
        graphemes: resources.graphemes,
        styles: &resources.styles,
        resolveColor: resolveRuntimeColor
      )
    } else {
      semantics = try paintSubtree(
        node,
        into: &destination,
        damage: damage,
        focusHighlight: nil,
        selectionHighlight: nil,
        resources: &resources
      )
    }
    if node.isPresentationOnly == false,
       damage == nil || rebuildSemanticAncestors || node.primitive(as: (any SemanticRenderable).self) != nil
    {
      retainedSemantics[node.id] = semantics
    }
    return semantics
  }

  private func paintSubtree(
    _ node: MountedNode,
    into surface: inout Surface,
    damage: DamageTracker?,
    focusHighlight: LinearRGBA?,
    selectionHighlight: LinearRGBA?,
    resources: inout ControlRenderResources
  ) throws -> [SemanticNode] {
    var semantics: [SemanticNode] = []
    if let renderable = node.primitive(as: (any SemanticRenderable).self), let frame = node.cachedFrame {
      let clip = clips[node.id] ?? node.paintBounds.intersection(surface.bounds) ?? .zero
      let paintClip = clip.intersection(frame).flatMap { $0.intersection(surface.bounds) } ?? .zero
      let environment = node.environment
      var semantic = try renderable.paint(
        into: &surface,
        context: PaintContext(
          clip: paintClip,
          origin: frame.origin,
          environment: PaintEnvironmentValues { identifier in
            environment.value(forKeyIdentifier: identifier)
          },
          frameSize: frame.size
        ),
        resources: &resources
      )
      semantic = clipped(semantic, to: clip)
      if node.id == focusedNodeID {
        semantic.state.insert(.focused)
      }
      semantics.append(semantic)
    }
    let children =
      paintContributorIDs == nil || rebuildSemanticAncestors
        ? sceneChildren(of: node)
        : paintChildCache[node.id] ?? []
    for child in children {
      let childSemantics = try paintNode(child, into: &surface, damage: damage, resources: &resources)
      semantics.append(contentsOf: childSemantics)
    }

    let state = semanticState(in: semantics)
    let highlight =
      state.contains(.focused)
        ? focusHighlight
        : state.contains(.selected) ? selectionHighlight : nil
    let presentation = presentations[node.id] ?? Presentation()
    if let border = highlight ?? presentation.border, let frame = node.cachedFrame {
      try drawBorder(around: frame, color: border.rgba, clip: clips[node.id] ?? frame, into: &surface, resources: &resources)
    }
    if let highlight {
      try surface.transformStyles(in: node.paintBounds, styles: &resources.styles) { style in
        CellStyle(
          foreground: .rgba(highlight.rgba),
          background: .rgba(highlight.rgba),
          attributes: style.attributes
        )
      }
    }
    if let symbol = presentation.transition?.symbol, let character = symbol.first,
       let point = firstVisibleCell(in: node.paintBounds, on: surface)
    {
      let cell = surface[point]
      let grapheme = try resources.graphemes.intern(character)
      _ = try surface.write(graphemeID: grapheme, at: point, styleID: cell.styleID, clip: clips[node.id])
    }
    return semantics
  }

  private func contributes(_ node: MountedNode, to damage: DamageTracker) -> Bool {
    if let paintContributorIDs {
      return paintContributorIDs.contains(node.id)
    }
    if damage.rectangles.contains(where: node.paintBounds.intersects) {
      return true
    }
    return sceneChildren(of: node).contains { contributes($0, to: damage) }
  }

  private func hasStructuralInvalidation(in node: MountedNode?) -> Bool {
    guard let node else { return false }
    return node.localDirtyFlags.contains(.structure)
      || node.children.contains { hasStructuralInvalidation(in: $0) }
  }

  private func sceneChildren(of parent: MountedNode) -> [MountedNode] {
    if let cached = sceneChildCache[parent.id] {
      return cached
    }
    return sceneChildrenUncached(of: parent)
  }

  private func rebuildSceneChildCache(graph: ViewGraph) {
    sceneChildCache.removeAll(keepingCapacity: true)
    sceneRowIndex.removeAll(keepingCapacity: true)
    func cache(_ node: MountedNode) {
      for row in node.paintBounds.minY ..< node.paintBounds.maxY {
        sceneRowIndex[row, default: []].append(node)
      }
      let children = sceneChildrenUncached(of: node)
      sceneChildCache[node.id] = children
      for child in children {
        cache(child)
      }
    }
    if let root = graph.root {
      cache(root)
    }
    for root in scenePresentationRoots(parentID: nil) {
      cache(root)
    }
  }

  private func contributors(to damage: DamageTracker) -> (ids: Set<NodeID>, children: [NodeID: [MountedNode]]) {
    var contributors: Set<NodeID> = []
    var childIDs: [NodeID: Set<NodeID>] = [:]
    for rect in damage.rectangles {
      for row in rect.minY ..< rect.maxY {
        for node in sceneRowIndex[row] ?? [] where node.paintBounds.intersects(rect) {
          var current: MountedNode? = node
          while let candidate = current {
            contributors.insert(candidate.id)
            if let parent = candidate.parent {
              childIDs[parent.id, default: []].insert(candidate.id)
            } else if let parentID = candidate.presentationPlacement?.parentID,
                      let parent = graph?.node(withID: parentID)
            {
              childIDs[parent.id, default: []].insert(candidate.id)
              current = parent
              continue
            }
            current = candidate.parent
          }
        }
      }
    }
    var children: [NodeID: [MountedNode]] = [:]
    for (parentID, ids) in childIDs {
      children[parentID] = (sceneChildCache[parentID] ?? []).filter { ids.contains($0.id) }
    }
    return (contributors, children)
  }

  private func sceneChildrenUncached(of parent: MountedNode) -> [MountedNode] {
    var siblings = parent.children
    let retained = scenePresentationRoots(parentID: parent.id).sorted {
      ($0.presentationPlacement?.siblingIndex ?? Int.max)
        < ($1.presentationPlacement?.siblingIndex ?? Int.max)
    }
    for node in retained {
      let placement = node.presentationPlacement
      let index: Int = if let nextID = placement?.nextSiblingID,
                          let nextIndex = siblings.firstIndex(where: { $0.id == nextID })
      {
        nextIndex
      } else if let previousID = placement?.previousSiblingID,
                let previousIndex = siblings.lastIndex(where: { $0.id == previousID })
      {
        previousIndex + 1
      } else {
        min(placement?.siblingIndex ?? siblings.count, siblings.count)
      }
      siblings.insert(node, at: index)
    }
    return siblings.enumerated().sorted {
      let lhs = ($0.element.hitTestMetadata.zIndex, $0.offset)
      let rhs = ($1.element.hitTestMetadata.zIndex, $1.offset)
      return lhs < rhs
    }.map(\.element)
  }

  private func scenePresentationRoots(parentID: NodeID?) -> [MountedNode] {
    graph?.presentationRoots.filter { $0.presentationPlacement?.parentID == parentID } ?? []
  }

  private func firstVisibleCell(in bounds: CellRect, on surface: Surface) -> CellPoint? {
    guard let bounds = surface.bounds.intersection(bounds) else { return nil }
    for y in bounds.minY ..< bounds.maxY {
      for x in bounds.minX ..< bounds.maxX {
        let point = CellPoint(x: x, y: y)
        let cell = surface[point]
        if cell.isTransparent == false, cell.isContinuation == false {
          return point
        }
      }
    }
    return nil
  }

  private func semanticState(in nodes: [SemanticNode]) -> SemanticState {
    nodes.reduce(into: SemanticState()) { state, node in
      state.formUnion(node.state)
      state.formUnion(semanticState(in: node.children))
    }
  }

  private func drawBorder(
    around frame: CellRect,
    color: RGBA,
    clip: CellRect,
    into surface: inout Surface,
    resources: inout ControlRenderResources
  ) throws {
    guard frame.isEmpty == false else { return }
    let style = try resources.internPaintStyle(CellStyle(foreground: .rgba(color)))
    let horizontal = try resources.graphemes.intern("-")
    let vertical = try resources.graphemes.intern("|")
    for y in frame.minY ..< frame.maxY {
      for x in frame.minX ..< frame.maxX where y == frame.minY || y == frame.maxY - 1 || x == frame.minX || x == frame.maxX - 1 {
        let point = CellPoint(x: x, y: y)
        guard surface.bounds.contains(point), clip.contains(point) else { continue }
        let grapheme = y == frame.minY || y == frame.maxY - 1 ? horizontal : vertical
        _ = try surface.write(graphemeID: grapheme, at: point, styleID: style, clip: clip)
      }
    }
  }

  private func resolveRuntimeColor(_ color: Color?, role: CellColorRole) throws -> RGBA {
    switch color {
    case let .rgba(rgba): return rgba
    case let .semantic(semantic): throw ColorResolutionError.missing(semantic)
    case nil: return .black
    }
  }

  private func clipped(_ node: SemanticNode, to clip: CellRect) -> SemanticNode {
    var copy = node
    copy.frame = node.frame?.intersection(clip)
    copy.children = node.children.map { clipped($0, to: clip) }
    return copy
  }

  private func edgeInsets(_ value: FloatingEdgeInsets) -> EdgeInsets {
    EdgeInsets(
      top: nonnegative(value.top),
      leading: nonnegative(value.leading),
      bottom: nonnegative(value.bottom),
      trailing: nonnegative(value.trailing)
    )
  }

  private func nonnegative(_ value: Double) -> Int {
    max(0, quantize(value))
  }

  private func quantize(_ value: Double) -> Int {
    if value >= Double(Int.max) {
      return Int.max
    }
    if value <= Double(Int.min) {
      return Int.min
    }
    return Int(value.rounded(.toNearestOrAwayFromZero))
  }

  private func presentedHitTest(_ point: CellPoint, in node: MountedNode) -> MountedNode? {
    let modalScope = topmostModalScope(in: node)
    return presentedHitTest(point, in: node, requiredModalScope: modalScope)
  }

  private func presentedHitTest(
    _ point: CellPoint,
    in node: MountedNode,
    requiredModalScope: String?
  ) -> MountedNode? {
    guard node.paintBounds.contains(point) else { return nil }
    if node.hitTestMetadata.disablesDescendants {
      guard node.acceptsHitTesting else { return nil }
      return requiredModalScope == nil || node.activeModalScope == requiredModalScope ? node : nil
    }
    for child in sceneChildren(of: node).reversed() {
      if let match = presentedHitTest(point, in: child, requiredModalScope: requiredModalScope) {
        return match
      }
      // A presented overlay occludes the cells it paints: a point inside
      // one that matched nothing must not fall through to the content
      // beneath the overlay.
      if child.primitive(as: RuntimeOverlayItemPrimitive.self) != nil,
         child.paintBounds.contains(point)
      {
        return nil
      }
    }
    guard node.acceptsHitTesting else { return nil }
    return requiredModalScope == nil || node.activeModalScope == requiredModalScope ? node : nil
  }

  private func topmostModalScope(in node: MountedNode) -> String? {
    sceneChildren(of: node).reversed().lazy.compactMap { self.topmostModalScope(in: $0) }.first
      ?? node.hitTestMetadata.modalScope
  }

  private func moveFocus(backward: Bool, in graph: ViewGraph) {
    let modalScope = graph.root.flatMap(topmostModalScope)
    let nodes = graph.focusableNodes().filter {
      modalScope == nil || $0.activeModalScope == modalScope
    }.sorted {
      ($0.focusMetadata.order ?? Int.max, $0.id.rawValue) < ($1.focusMetadata.order ?? Int.max, $1.id.rawValue)
    }
    guard nodes.isEmpty == false else {
      setFocusedNodeID(nil, in: graph)
      return
    }
    guard let focusedNodeID, let index = nodes.firstIndex(where: { $0.id == focusedNodeID }) else {
      setFocusedNodeID(backward ? nodes.last?.id : nodes.first?.id, in: graph)
      return
    }
    let offset = backward ? nodes.count - 1 : 1
    setFocusedNodeID(nodes[(index + offset) % nodes.count].id, in: graph)
  }

  private func setFocusedNodeID(_ id: NodeID?, in graph: ViewGraph) {
    guard focusedNodeID != id else { return }
    requiresFullPaint = true
    if let focusedNodeID, let old = graph.node(withID: focusedNodeID) {
      old.primitive(as: (any ControlFocusHandler).self)?.controlFocusChanged(false)
      old.invalidate(.paint)
    }
    focusedNodeID = id
    if let id, let new = graph.node(withID: id) {
      new.primitive(as: (any ControlFocusHandler).self)?.controlFocusChanged(true)
      new.invalidate(.paint)
    }
  }

  private func synchronizeModalFocus(in graph: ViewGraph) {
    let newScopes = overlayHost?.orderedOverlays.filter(\.isModal).map(\.id.rawValue) ?? []
    let commonCount = zip(activeModalScopes, newScopes).prefix { $0 == $1 }.count

    for scope in activeModalScopes.dropFirst(commonCount).reversed() {
      let restoration = focusRestoration.removeValue(forKey: scope).flatMap(\.self)
      setFocusedNodeID(restoration, in: graph)
    }
    for scope in newScopes.dropFirst(commonCount) {
      focusRestoration[scope] = focusedNodeID
      setFocusedNodeID(preferredFocusableNode(in: scope, graph: graph)?.id, in: graph)
    }
    activeModalScopes = newScopes

    if let activeScope = newScopes.last,
       focusedNodeID.flatMap({ graph.node(withID: $0) })?.activeModalScope != activeScope
    {
      setFocusedNodeID(preferredFocusableNode(in: activeScope, graph: graph)?.id, in: graph)
    }
  }

  private func preferredFocusableNode(in scope: String, graph: ViewGraph) -> MountedNode? {
    if let overlayID = overlayHost?.orderedOverlays.first(where: { $0.id.rawValue == scope })?.id,
       let initialFocus = overlayHost?.initialFocus(for: overlayID),
       let node = graph.focusableNodes().first(where: {
         $0.activeModalScope == scope && $0.focusMetadata.id == initialFocus
       })
    {
      return node
    }
    return firstFocusableNode(in: scope, graph: graph)
  }

  private func firstFocusableNode(in scope: String, graph: ViewGraph) -> MountedNode? {
    graph.focusableNodes().filter { $0.activeModalScope == scope }.min {
      ($0.focusMetadata.order ?? Int.max, $0.id.rawValue)
        < ($1.focusMetadata.order ?? Int.max, $1.id.rawValue)
    }
  }

  private func activate(_ node: MountedNode) {
    node.primitive(as: (any ControlActivatable).self)?.activate()
  }
}
