@testable import TermKit
import Testing

@MainActor
struct PresentationConsumptionTests {
  @Test
  func `Ordinary declarative wrappers allocate no offscreen surfaces`() throws {
    let view = VStack(alignment: .leading) {
      Text("A")
      Text("B")
      Text("C")
    }
    .padding(1)
    .frame(width: 20, height: 5, alignment: .topLeading)
    let (runtime, _) = makeRuntime(view, size: CellSize(width: 20, height: 5))
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    #expect(runtime.incrementalCounters?.offscreenLayerCount == 0)
    #expect(runtime.incrementalCounters?.offscreenCellCount == 0)
  }

  @Test
  func `Opacity allocates one paint-bounded offscreen surface`() throws {
    let view = AnimatedTextView(text: "XY", opacity: 0.5)
    let (runtime, _) = makeRuntime(view, size: CellSize(width: 100, height: 40))
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    #expect(runtime.incrementalCounters?.offscreenLayerCount == 1)
    #expect(runtime.incrementalCounters?.offscreenCellCount == 2)
  }

  @Test
  func `Z-index defines both paint and hit-test order`() throws {
    let view = DescriptorView(
      NodeDescriptor(
        type: ZScene.self,
        children: [
          NodeDescriptor(
            type: Text.self,
            index: 0,
            primitive: Text("A"),
            hitTest: HitTestMetadata(isEnabled: true, zIndex: 10),
            dirtyOnUpdate: .layout
          ),
          NodeDescriptor(
            type: Text.self,
            index: 1,
            primitive: Text("B"),
            hitTest: HitTestMetadata(isEnabled: true, zIndex: 0),
            dirtyOnUpdate: .layout
          )
        ]
      )
    )
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 1, height: 1))
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    #expect(grapheme(at: .zero, presenter: presenter) == "A")
    #expect(runtime.graph.hitTest(.zero)?.hitTestMetadata.zIndex == 10)
  }

  @Test
  func `Runtime interaction respects disabled ancestry and the top modal scope`() throws {
    var backgroundActivations = 0
    var disabledActivations = 0
    var modalActivations = 0
    let background = interactiveButton("Background") { backgroundActivations += 1 }
    let disabled = NodeDescriptor(
      type: DisabledInteractionScope.self,
      index: 1,
      children: [interactiveButton("Disabled") { disabledActivations += 1 }],
      hitTest: HitTestMetadata(disablesDescendants: true),
      dirtyOnUpdate: .layout
    )
    let modal = NodeDescriptor(
      type: ModalInteractionScope.self,
      index: 2,
      children: [interactiveButton("Modal") { modalActivations += 1 }],
      hitTest: HitTestMetadata(disablesDescendants: false, zIndex: 100, modalScope: "confirmation"),
      dirtyOnUpdate: .layout
    )
    let view = DescriptorView(
      NodeDescriptor(
        type: InteractionScene.self,
        children: [background, disabled, modal]
      )
    )
    let (runtime, _) = makeRuntime(view, size: CellSize(width: 20, height: 3))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    let disabledNode = try #require(
      firstNode(runtime.graph.root) {
        $0.primitive(as: Button.self)?.label.plainText == "Disabled"
      }
    )
    #expect(disabledNode.isFocusable == false)
    #expect(disabledNode.acceptsHitTesting == false)

    try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
    try runtime.process(.input(.key(TerminalKeyEvent(key: .enter))))

    #expect(backgroundActivations == 0)
    #expect(disabledActivations == 0)
    #expect(modalActivations == 1)
  }

  @Test
  func `Nested opacity composites cumulative alpha over the actual backdrop`() throws {
    let red = CellStyle(foreground: .rgba(RGBA(red: 1, green: 0, blue: 0)))
    let blue = CellStyle(foreground: .rgba(RGBA(red: 0, green: 0, blue: 1)))
    let lower = Text(runs: [StyledRun("R", style: red), StyledRun("B", style: blue)], id: "lower")
      .graphBody[0]
    let upper = Text("WW", style: CellStyle(foreground: .rgba(.white))).graphBody[0]
      .presentationValue(0.5, for: .opacity)
    let group = NodeDescriptor(type: OpacityGroup.self, children: [upper])
      .presentationValue(0.5, for: .opacity)
    let root = DescriptorView(NodeDescriptor(type: OpacityScene.self, children: [lower, group]))
    let (runtime, presenter) = makeRuntime(root, size: CellSize(width: 2, height: 1))
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    let overRed = try #require(try rgba(style(at: .zero, presenter: presenter).foreground))
    let overBlue = try #require(try rgba(style(at: CellPoint(x: 1), presenter: presenter).foreground))
    #expect(overRed.redByte == 255)
    #expect(abs(Int(overRed.greenByte) - 137) <= 1)
    #expect(abs(Int(overRed.blueByte) - 137) <= 1)
    #expect(abs(Int(overBlue.redByte) - 137) <= 1)
    #expect(abs(Int(overBlue.greenByte) - 137) <= 1)
    #expect(overBlue.blueByte == 255)
    #expect(runtime.incrementalCounters?.offscreenLayerCount == 2)
    #expect(runtime.incrementalCounters?.offscreenCellCount == 4)
  }

  @Test
  func `Retained middle sibling keeps its original paint position`() throws {
    let view = RetainedSiblingHost(includesMiddle: true)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 1, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.includesMiddle = false }
    let removalStart = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)

    _ = try runtime.renderIfDue(at: removalStart)
    _ = try runtime.renderIfDue(at: removalStart.advanced(by: .milliseconds(500)))

    #expect(runtime.graph.presentationRoots.isEmpty == false)
    #expect(grapheme(at: .zero, presenter: presenter) == "C")
  }

  @Test
  func `Ancestor foreground styles only cells painted by its subtree`() throws {
    let lower = Text("GG", style: CellStyle(foreground: .rgba(RGBA(red: 0, green: 1, blue: 0))))
      .graphBody[0]
    let upper = NodeDescriptor(
      type: FrameLayout.self,
      primitive: LayoutPrimitive.frame(FrameLayout(width: 2, alignment: .topLeading)),
      children: [Text("X").graphBody[0]]
    ).presentationValue(LinearRGBA(red: 1, green: 0, blue: 0), for: .foregroundColor)
    let root = DescriptorView(NodeDescriptor(type: StyleScene.self, children: [lower, upper]))
    let (runtime, presenter) = makeRuntime(root, size: CellSize(width: 2, height: 1))
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    let first = try #require(try rgba(style(at: .zero, presenter: presenter).foreground))
    let second = try #require(try rgba(style(at: CellPoint(x: 1), presenter: presenter).foreground))
    #expect(first.redByte == 255)
    #expect(first.greenByte == 0)
    #expect(second.redByte == 0)
    #expect(second.greenByte == 255)
    #expect(runtime.incrementalCounters?.offscreenLayerCount == 0)
  }

  @Test
  func `Failed presentation keeps the last accepted raster and semantics for retry`() throws {
    let view = AnimatedTextView(text: "X", foreground: LinearRGBA(.black))
    let session = FakeTerminalSession()
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: view,
      presenter: presenter,
      terminalSize: CellSize(width: 1, height: 1),
      timeSource: DeterministicTimeSource()
    )
    try runtime.start()
    let accepted = try #require(try runtime.renderIfDue(at: .zero))
    let acceptedSurface = try #require(presenter.frontSurface)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.foreground = LinearRGBA(.white) }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    let previousSurface = try #require(presenter.frontSurface)
    session.presentationError = .expected

    #expect(throws: FakeTerminalSession.PresentationError.expected) {
      try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))
    }
    #expect(presenter.frontSurface == previousSurface)
    #expect(runtime.semantics == accepted.semantics)

    session.presentationError = nil
    let retry = try #require(
      try runtime.renderIfDue(
        at: start.advanced(by: .milliseconds(500)).advanced(by: FrameScheduler.minimumFrameInterval)
      )
    )
    #expect(retry.semantics == accepted.semantics)
    #expect(presenter.frontSurface != acceptedSurface)
  }

  @Test
  func `Runtime consumes color and opacity presentation samples`() throws {
    let view = AnimatedTextView(text: "X", foreground: LinearRGBA(.black))
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 1, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    update(runtime, animation: .linear(duration: .seconds(1))) {
      view.foreground = LinearRGBA(.white)
    }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    let revision = runtime.graph.revision
    let counters = try #require(runtime.incrementalCounters)
    let evaluationCount = view.evaluationCount
    let midpoint = start.advanced(by: .milliseconds(500))
    let result = try #require(try runtime.renderIfDue(at: midpoint))
    let style = try style(at: .zero, presenter: presenter)
    let foreground = try #require(style.foreground)
    guard case let .rgba(rgba) = foreground else {
      Issue.record("Expected explicit sampled color")
      return
    }

    #expect(abs(Int(rgba.redByte) - 188) <= 1)
    #expect(abs(Int(rgba.greenByte) - 188) <= 1)
    #expect(abs(Int(rgba.blueByte) - 188) <= 1)
    #expect(result.stats.activeAnimationCount > 0)
    #expect(result.stats.reconciliationDuration == .zero)
    #expect(result.stats.layoutDuration == .zero)
    #expect(runtime.graph.revision == revision)
    #expect(runtime.incrementalCounters?.layoutPassCount == counters.layoutPassCount)
    #expect(runtime.incrementalCounters?.measurementCount == counters.measurementCount)
    #expect(runtime.incrementalCounters?.paintVisitCount ?? 0 > counters.paintVisitCount)
    #expect(view.evaluationCount == evaluationCount)
    #expect(runtime.nextDeadline(at: midpoint) != nil)
  }

  @Test
  func `Runtime evaluates an animatable modifier with mounted presentation samples`() throws {
    let view = ModifierAnimationHost(value: 0)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 12, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    update(runtime, animation: .linear(duration: .seconds(1))) { view.value = 10 }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

    #expect(text(presenter).hasPrefix("value:5.0"))
  }

  @Test
  func `Reduced motion toast reaches expiry through the runtime scheduler`() throws {
    var expiredID: OverlayID?
    let toast = Toast(
      id: "saved",
      message: "Saved",
      createdAt: .zero,
      duration: .milliseconds(500),
      fade: .milliseconds(100)
    )
    let (runtime, _) = makeRuntime(
      toast.timeline { expiredID = $0 },
      size: CellSize(width: 20, height: 3),
      motionPolicy: .reduced
    )
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)
    #expect(runtime.nextDeadline(at: .zero) == .zero.advanced(by: .milliseconds(500)))

    _ = try runtime.renderIfDue(at: .zero.advanced(by: .milliseconds(500)))
    #expect(expiredID == "saved")
    #expect(runtime.nextDeadline(at: .zero.advanced(by: .milliseconds(500))) == nil)
  }

  @Test
  func `Sampled background color styles every painted cell without filling empty cells`() throws {
    let view = AnimatedTextView(text: "XY", background: LinearRGBA(.black))
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 3, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.background = LinearRGBA(.white) }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

    for x in 0 ... 1 {
      guard case let .rgba(color)? = try style(at: CellPoint(x: x), presenter: presenter).background else {
        Issue.record("Expected sampled background color")
        return
      }
      #expect(abs(Int(color.redByte) - 188) <= 1)
    }
    #expect(presenter.frontSurface?[CellPoint(x: 2)].styleID == .default)
  }

  @Test
  func `Sampled border is a stable one-cell frame with sampled color`() throws {
    let view = AnimatedTextView(text: "abc\ndef\nghi", border: LinearRGBA(.black))
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 3, height: 3))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.border = LinearRGBA(.white) }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

    #expect(grapheme(at: CellPoint(x: 1, y: 0), presenter: presenter) == "-")
    #expect(grapheme(at: CellPoint(x: 0, y: 1), presenter: presenter) == "|")
    #expect(grapheme(at: CellPoint(x: 1, y: 1), presenter: presenter) == "e")
    guard case let .rgba(color)? = try style(at: .zero, presenter: presenter).foreground else {
      Issue.record("Expected sampled border color")
      return
    }
    #expect(abs(Int(color.redByte) - 188) <= 1)
  }

  @Test
  func `Half opacity composites white over black in linear light`() throws {
    let view = AnimatedTextView(text: "X", foreground: LinearRGBA(.white), opacity: 1)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 1, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.opacity = 0 }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

    let style = try style(at: .zero, presenter: presenter)
    guard case let .rgba(rgba)? = style.foreground else {
      Issue.record("Expected composited color")
      return
    }
    #expect(abs(Int(rgba.redByte) - 188) <= 1)
  }

  @Test
  func `Runtime consumes geometry, reveal, and localized damage samples`() throws {
    let view = AnimatedTextView(text: "界A", offset: .zero, reveal: 1)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 8, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) {
      view.offset = CellVector(x: 4)
      view.reveal = 0
    }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    let revision = runtime.graph.revision
    let counters = try #require(runtime.incrementalCounters)
    let evaluationCount = view.evaluationCount
    let midpoint = try #require(try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500))))
    let node = try #require(deepestNode(runtime.graph.root))

    #expect(node.cachedFrame?.origin.x == 2)
    #expect(node.paintBounds.width == 2)
    #expect(text(presenter).contains("界"))
    #expect(text(presenter).contains("�") == false)
    #expect(midpoint.stats.scannedCellCount < 8)
    #expect(midpoint.stats.reconciliationDuration == .zero)
    #expect(runtime.graph.revision == revision)
    #expect(runtime.incrementalCounters?.layoutPassCount == counters.layoutPassCount + 1)
    #expect(view.evaluationCount == evaluationCount)

    _ = try runtime.renderIfDue(at: start.advanced(by: .seconds(1)))
    #expect(deepestNode(runtime.graph.root)?.paintBounds.isEmpty == true)
    #expect(text(presenter).contains("界") == false)
  }

  @Test
  func `A malformed presentation target throws before spatial quantization`() throws {
    var offset = CellVector.zero
    offset.x = .nan
    let descriptor = Text("X").graphBody[0].attribute(
      AnimatablePropertyAttribute(
        property: .offset,
        value: offset,
        transaction: Transaction(animationTime: .zero)
      )
    )
    let (runtime, _) = makeRuntime(DescriptorView(descriptor), size: CellSize(width: 1, height: 1))
    try runtime.start()

    do {
      _ = try runtime.renderIfDue(at: .zero)
      Issue.record("Expected malformed presentation target error.")
    } catch let RuntimeError.invalidPresentationValue(property, value) {
      #expect(property == PresentationProperties.offset.key)
      #expect(value.lowercased().contains("nan"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func `Clip inset midpoint matches painted, semantic, and hit-test geometry`() throws {
    let view = AnimatedTextView(text: "ABCD", clipInsets: .zero)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 4, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) {
      view.clipInsets = FloatingEdgeInsets(leading: 2, trailing: 2)
    }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    let result = try #require(try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500))))
    let leaf = try #require(deepestNode(runtime.graph.root))

    #expect(leaf.paintBounds == CellRect(x: 1, y: 0, width: 2, height: 1))
    #expect(result.semantics.node(withID: "text")?.frame == leaf.paintBounds)
    #expect(grapheme(at: CellPoint(x: 0), presenter: presenter) == " ")
    #expect(grapheme(at: CellPoint(x: 1), presenter: presenter) == "B")
    #expect(grapheme(at: CellPoint(x: 2), presenter: presenter) == "C")
    #expect(grapheme(at: CellPoint(x: 3), presenter: presenter) == " ")
    #expect(runtime.graph.hitTest(CellPoint(x: 0)) == nil)
  }

  @Test
  func `Parent and child offsets quantize their accumulated positive and negative values once`() throws {
    for target in [-0.5, 0.5] {
      let view = NestedOffsetView(parentOffset: target / 2, childOffset: 0)
      let (runtime, _) = makeRuntime(view, size: CellSize(width: 8, height: 1))
      try runtime.start()
      _ = try runtime.renderIfDue(at: .zero)
      update(runtime, animation: .linear(duration: .seconds(1))) { view.childOffset = target }
      let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
      _ = try runtime.renderIfDue(at: start)
      _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

      let expected = target < 0 ? -1 : 1
      #expect(deepestNode(runtime.graph.root)?.cachedFrame?.minX == expected)
    }
  }

  @Test
  func `Animated frame, padding, and spacing override declarative layout`() throws {
    let view = AnimatedLayoutView(width: 8, padding: FloatingEdgeInsets(), spacing: 0)
    let (runtime, _) = makeRuntime(view, size: CellSize(width: 12, height: 4))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) {
      view.width = 4
      view.padding = FloatingEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
      view.spacing = 2
    }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))
    let frames = descendantFrames(of: runtime.graph.root)

    #expect(frames.contains { $0.width == 6 })
    #expect(frames.contains { $0.origin.x == 1 && $0.origin.y == 1 })
    #expect(frames.contains { $0.origin.y == 3 })
  }

  @Test
  func `Scroll viewport consumes sampled position`() throws {
    let view = AnimatedScrollView(position: .zero)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 2, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.position = CellVector(x: 4) }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

    #expect(text(presenter).hasPrefix("CD"))
    #expect(runtime.graph.root?.paintBounds == CellRect(x: 0, y: 0, width: 2, height: 1))
  }

  @Test
  func `Runtime focus activates sampled focus highlight`() throws {
    let view = HighlightButtonView()
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 3, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
    let next = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: next)

    let style = try style(at: CellPoint(x: 1), presenter: presenter)
    #expect(runtime.graph.root?.children.first?.presentationValue(.focusHighlight) != nil)
    #expect(runtime.graph.focusableNodes().first?.id != nil)
    guard case let .rgba(color)? = style.foreground else {
      Issue.record("Expected focus highlight")
      return
    }
    #expect(color.redByte == 255)
    #expect(color.greenByte == 0)
    #expect(color.blueByte == 0)
  }

  @Test
  func `Selected semantics activate sampled selection highlight`() throws {
    let view = SelectedHighlightView()
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 1, height: 1))
    try runtime.start()
    let result = try #require(try runtime.renderIfDue(at: .zero))
    runtime.invalidate()
    _ = try runtime.renderIfDue(at: TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval))

    let style = try style(at: .zero, presenter: presenter)
    #expect(runtime.graph.root?.children.first?.presentationTarget(for: .selectionHighlight) != nil)
    #expect(result.semantics.node(withID: "selected")?.state.contains(.selected) == true)
    #expect(runtime.graph.root?.children.first?.paintBounds == CellRect(x: 0, y: 0, width: 1, height: 1))
    let color: RGBA
    if case let .rgba(value)? = style.background {
      color = value
    } else if case let .rgba(value)? = style.foreground {
      color = value
    } else {
      Issue.record("Expected selection highlight")
      return
    }
    #expect(color.greenByte == 255)
  }

  @Test
  func `Insertion and removal transitions render retained presentation`() throws {
    let view = TransitionHost(isVisible: false)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 1, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.isVisible = true }
    let insertionStart = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: insertionStart)
    #expect(text(presenter).contains("X") == false)
    _ = try runtime.renderIfDue(at: insertionStart.advanced(by: .milliseconds(500)))
    #expect(text(presenter).contains("X"))

    let insertionEnd = insertionStart.advanced(by: .seconds(1))
    _ = try runtime.renderIfDue(at: insertionEnd)
    update(runtime, at: insertionEnd, animation: .linear(duration: .seconds(1))) { view.isVisible = false }
    let removalStart = insertionEnd.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: removalStart)
    _ = try runtime.renderIfDue(at: removalStart.advanced(by: .milliseconds(500)))
    #expect(runtime.graph.presentationRoots.isEmpty == false)
    #expect(text(presenter).contains("X"))
    #expect(runtime.graph.presentationRoots.allSatisfy { $0.isInteractive == false })

    _ = try runtime.renderIfDue(at: removalStart.advanced(by: .seconds(1)))
    #expect(runtime.graph.presentationRoots.isEmpty)
    #expect(text(presenter).contains("X") == false)
  }

  @Test
  func `Move transition uses insertion and removal directions`() throws {
    let view = TransitionHost(isVisible: false, originX: 4, transition: .move(edge: .leading, distance: 4))
    let (runtime, _) = makeRuntime(view, size: CellSize(width: 8, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.isVisible = true }
    let insertionStart = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: insertionStart)
    _ = try runtime.renderIfDue(at: insertionStart.advanced(by: .milliseconds(500)))
    #expect(deepestNode(runtime.graph.root)?.cachedFrame?.minX == 2)

    let insertionEnd = insertionStart.advanced(by: .seconds(1))
    _ = try runtime.renderIfDue(at: insertionEnd)
    update(runtime, at: insertionEnd, animation: .linear(duration: .seconds(1))) { view.isVisible = false }
    let removalStart = insertionEnd.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: removalStart)
    _ = try runtime.renderIfDue(at: removalStart.advanced(by: .milliseconds(500)))
    #expect(runtime.graph.presentationRoots.first?.cachedFrame?.minX == 2)
  }

  @Test
  func `Reveal and wipe honor edges without splitting wide atoms`() throws {
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    for (edge, expected) in [(TransitionEdge.top, "AB "), (.bottom, " BC")] {
      let host = TransitionHost(isVisible: false, text: "A\nB\nC", transition: .reveal(edge: edge))
      let (runtime, presenter) = makeRuntime(host, size: CellSize(width: 1, height: 3))
      try runtime.start()
      _ = try runtime.renderIfDue(at: .zero)
      update(runtime, animation: .linear(duration: .seconds(1))) { host.isVisible = true }
      _ = try runtime.renderIfDue(at: start)
      _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))
      #expect(text(presenter) == expected)
    }

    for (edge, expected) in [(TransitionEdge.leading, "AB "), (.trailing, " BC")] {
      let host = TransitionHost(isVisible: false, text: "ABC", transition: .wipe(edge: edge))
      let (runtime, presenter) = makeRuntime(host, size: CellSize(width: 3, height: 1))
      try runtime.start()
      _ = try runtime.renderIfDue(at: .zero)
      update(runtime, animation: .linear(duration: .seconds(1))) { host.isVisible = true }
      _ = try runtime.renderIfDue(at: start)
      _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))
      #expect(text(presenter) == expected)
    }

    let wipeHost = TransitionHost(isVisible: false, text: "A界B", transition: .wipe(edge: .trailing))
    let (wipeRuntime, wipePresenter) = makeRuntime(wipeHost, size: CellSize(width: 4, height: 1))
    try wipeRuntime.start()
    _ = try wipeRuntime.renderIfDue(at: .zero)
    update(wipeRuntime, animation: .linear(duration: .seconds(1))) { wipeHost.isVisible = true }
    _ = try wipeRuntime.renderIfDue(at: start)
    _ = try wipeRuntime.renderIfDue(at: start.advanced(by: .milliseconds(500)))
    #expect(text(wipePresenter).contains("界") == false)
    #expect(text(wipePresenter).contains("�") == false)
    #expect(grapheme(at: CellPoint(x: 3), presenter: wipePresenter) == "B")
  }

  @Test
  func `Symbol frames replace the first visible cell and retain its style`() throws {
    let transition = AnyTransition.symbolFrames(SymbolFrames([".", "o", "O"]))
      .combined(with: .wipe(edge: .trailing))
    let view = TransitionHost(isVisible: false, text: "ABC", transition: transition)
    let (runtime, presenter) = makeRuntime(view, size: CellSize(width: 3, height: 1))
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    update(runtime, animation: .linear(duration: .seconds(1))) { view.isVisible = true }
    let start = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try runtime.renderIfDue(at: start)
    _ = try runtime.renderIfDue(at: start.advanced(by: .milliseconds(500)))

    #expect(grapheme(at: CellPoint(x: 0), presenter: presenter) == " ")
    #expect(grapheme(at: CellPoint(x: 1), presenter: presenter) == "o")
  }

  @Test
  func `Reduced motion applies final presentation without cadence`() throws {
    let view = AnimatedTextView(text: "X", offset: CellVector(x: 3))
    let (runtime, _) = makeRuntime(view, size: CellSize(width: 4, height: 1), motionPolicy: .reduced)
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    #expect(runtime.graph.root?.children.first?.presentationTarget(for: .offset) == CellVector(x: 3))
    #expect(runtime.graph.root?.paintBounds == CellRect(x: 0, y: 0, width: 4, height: 1))
    #expect(runtime.nextDeadline(at: .zero) == nil)
  }

  private func makeRuntime(
    _ view: some View,
    size: CellSize,
    motionPolicy: MotionPolicy = .standard
  ) -> (Runtime, FramePresenter) {
    let presenter = FramePresenter(session: FakeTerminalSession())
    return (
      Runtime(
        view: view,
        presenter: presenter,
        terminalSize: size,
        motionPolicy: motionPolicy,
        timeSource: DeterministicTimeSource()
      ),
      presenter
    )
  }

  private func update(
    _ runtime: Runtime,
    at instant: TimeInstant = .zero,
    animation: Animation,
    _ body: () -> Void
  ) {
    var transaction = Transaction(animation: animation, animationTime: instant)
    withTransaction(transaction) {
      body()
      transaction = Transaction.current
      runtime.invalidate(transaction: transaction)
    }
  }

  private func style(at point: CellPoint, presenter: FramePresenter) throws -> CellStyle {
    let surface = try #require(presenter.frontSurface)
    return try #require(presenter.resources.styles.value(for: surface[point].styleID))
  }

  private func grapheme(at point: CellPoint, presenter: FramePresenter) -> String? {
    guard let cell = presenter.frontSurface?[point] else { return nil }
    return presenter.resources.graphemes.value(for: cell.graphemeID)
  }

  private func descendantFrames(of node: MountedNode?) -> [CellRect] {
    guard let node else { return [] }
    return [node.cachedFrame].compactMap(\.self) + node.children.flatMap { descendantFrames(of: $0) }
  }

  private func firstNode(_ node: MountedNode?, matching predicate: (MountedNode) -> Bool) -> MountedNode? {
    guard let node else { return nil }
    if predicate(node) {
      return node
    }
    for child in node.children {
      if let match = firstNode(child, matching: predicate) {
        return match
      }
    }
    return nil
  }

  private func interactiveButton(_ title: String, action: @escaping @MainActor @Sendable () -> Void) -> NodeDescriptor {
    NodeDescriptor(
      type: Button.self,
      primitive: Button(title, action: action),
      focus: FocusMetadata(isFocusable: true),
      hitTest: HitTestMetadata(isEnabled: true),
      dirtyOnUpdate: .layout
    )
  }

  private func deepestNode(_ node: MountedNode?) -> MountedNode? {
    guard let node else { return nil }
    return node.children.first.map(deepestNode) ?? node
  }

  private func text(_ presenter: FramePresenter) -> String {
    guard let surface = presenter.frontSurface else { return "" }
    return surface.cells.compactMap { cell in
      cell.isContinuation ? nil : presenter.resources.graphemes.value(for: cell.graphemeID)
    }.joined()
  }
}

private enum ZScene {}
private enum InteractionScene {}
private enum DisabledInteractionScope {}
private enum ModalInteractionScope {}
private enum OpacityScene {}
private enum OpacityGroup {}
private enum StyleScene {}

@MainActor
private final class RetainedSiblingHost: View {
  var includesMiddle: Bool

  init(includesMiddle: Bool) {
    self.includesMiddle = includesMiddle
  }

  var graphBody: [NodeDescriptor] {
    var children = [
      keyedText("A", key: "a"),
      keyedText("C", key: "c")
    ]
    if includesMiddle {
      children.insert(keyedText("B", key: "b").transition(.opacity), at: 1)
    }
    return [NodeDescriptor(type: RetainedSiblingHost.self, children: children)]
  }

  private func keyedText(_ text: String, key: String) -> NodeDescriptor {
    NodeDescriptor(type: Text.self, key: key, primitive: Text(text), dirtyOnUpdate: .layout)
  }
}

@MainActor
private final class AnimatedTextView: View {
  let text: String
  var foreground: LinearRGBA?
  var background: LinearRGBA?
  var border: LinearRGBA?
  var opacity: Double?
  var offset: CellVector?
  var reveal: Double?
  var clipInsets: FloatingEdgeInsets?
  private(set) var evaluationCount = 0

  init(
    text: String,
    foreground: LinearRGBA? = nil,
    background: LinearRGBA? = nil,
    border: LinearRGBA? = nil,
    opacity: Double? = nil,
    offset: CellVector? = nil,
    reveal: Double? = nil,
    clipInsets: FloatingEdgeInsets? = nil
  ) {
    self.text = text
    self.foreground = foreground
    self.background = background
    self.border = border
    self.opacity = opacity
    self.offset = offset
    self.reveal = reveal
    self.clipInsets = clipInsets
  }

  var graphBody: [NodeDescriptor] {
    evaluationCount += 1
    var descriptor = Text(text).graphBody[0]
    if let foreground {
      descriptor = descriptor.presentationValue(foreground, for: .foregroundColor)
    }
    if let background {
      descriptor = descriptor.presentationValue(background, for: .backgroundColor)
    }
    if let border {
      descriptor = descriptor.presentationValue(border, for: .borderColor)
    }
    if let opacity {
      descriptor = descriptor.presentationValue(opacity, for: .opacity)
    }
    if let offset {
      descriptor = descriptor.presentationValue(offset, for: .offset)
    }
    if let reveal {
      descriptor = descriptor.presentationValue(reveal, for: .clipReveal)
    }
    if let clipInsets {
      descriptor = descriptor.presentationValue(clipInsets, for: .clipInsets)
    }
    return [descriptor]
  }
}

@MainActor
private final class ModifierAnimationHost: View {
  var value: Double

  init(value: Double) {
    self.value = value
  }

  var graphBody: [NodeDescriptor] {
    Text("value").modifier(ValueLabelModifier(animatableData: value)).graphBody
  }
}

private struct ValueLabelModifier: AnimatableModifier {
  var animatableData: Double

  func body(content: Text) -> Text {
    Text("\(content.plainText):\(animatableData)")
  }
}

@MainActor
private final class AnimatedLayoutView: View {
  var width: Double
  var padding: FloatingEdgeInsets
  var spacing: Double

  init(width: Double, padding: FloatingEdgeInsets, spacing: Double) {
    self.width = width
    self.padding = padding
    self.spacing = spacing
  }

  var graphBody: [NodeDescriptor] {
    let stack = NodeDescriptor.makeDeclarative(
      VStack(alignment: .leading) {
        Text("A")
        Text("B")
      }
    )
    .presentationValue(spacing, for: .spacing)
    let padding = NodeDescriptor(
      type: PaddingLayout.self,
      primitive: LayoutPrimitive.padding(PaddingLayout(.zero)),
      children: [stack]
    ).presentationValue(padding, for: .padding)
    return [
      NodeDescriptor(
        type: FrameLayout.self,
        primitive: LayoutPrimitive.frame(FrameLayout(width: 8, alignment: .topLeading)),
        children: [padding]
      ).presentationValue(width, for: .frameWidth)
    ]
  }
}

@MainActor
private final class AnimatedScrollView: View {
  var position: CellVector
  init(position: CellVector) {
    self.position = position
  }

  var graphBody: [NodeDescriptor] {
    let content = Text("ABCDEF").graphBody[0]
    return [
      NodeDescriptor(
        type: ScrollViewport.self,
        primitive: LayoutPrimitive.scrollViewport(ScrollViewportLayout(width: 2, height: 1)),
        children: [content]
      ).presentationValue(position, for: .scrollPosition)
    ]
  }
}

@MainActor
private struct HighlightButtonView: View {
  var graphBody: [NodeDescriptor] {
    [
      Button("Go") {}.graphBody[0]
        .presentationValue(LinearRGBA(red: 1, green: 0, blue: 0), for: .focusHighlight)
    ]
  }
}

@MainActor
private struct SelectedHighlightView: View {
  var graphBody: [NodeDescriptor] {
    [
      NodeDescriptor(type: SelectedRenderable.self, primitive: SelectedRenderable())
        .presentationValue(LinearRGBA(red: 0, green: 1, blue: 0), for: .selectionHighlight)
    ]
  }
}

private struct SelectedRenderable: SemanticRenderable {
  func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    CellSize(width: 1, height: 1)
  }

  func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let grapheme = try resources.graphemes.intern("S")
    _ = try surface.write(graphemeID: grapheme, at: context.origin, clip: context.clip)
    return SemanticNode(
      id: "selected",
      role: .listItem,
      state: .selected,
      frame: CellRect(origin: context.origin, size: CellSize(width: 1, height: 1))
    )
  }
}

@MainActor
private final class TransitionHost: View {
  var isVisible: Bool
  let text: String
  let originX: Double
  let transition: AnyTransition

  init(
    isVisible: Bool,
    text: String = "X",
    originX: Double = 0,
    transition: AnyTransition = .opacity
  ) {
    self.isVisible = isVisible
    self.text = text
    self.originX = originX
    self.transition = transition
  }

  var graphBody: [NodeDescriptor] {
    let child = isVisible ? [Text(text).graphBody[0].transition(transition)] : []
    return [
      NodeDescriptor(type: TransitionHost.self, children: child)
        .presentationValue(CellVector(x: originX), for: .offset)
    ]
  }
}

@MainActor
private final class NestedOffsetView: View {
  let parentOffset: Double
  var childOffset: Double
  init(parentOffset: Double, childOffset: Double) {
    self.parentOffset = parentOffset
    self.childOffset = childOffset
  }

  var graphBody: [NodeDescriptor] {
    let child = Text("X").graphBody[0]
      .presentationValue(CellVector(x: childOffset), for: .offset)
    return [
      NodeDescriptor(type: NestedOffsetView.self, children: [child])
        .presentationValue(CellVector(x: parentOffset), for: .offset)
    ]
  }
}

extension TimeInstant {
  fileprivate static func milliseconds(_ value: Int64) -> TimeInstant {
    .zero.advanced(by: .milliseconds(value))
  }

  fileprivate static func seconds(_ value: Int64) -> TimeInstant {
    .zero.advanced(by: .seconds(Double(value)))
  }
}

private func rgba(_ color: Color?) -> RGBA? {
  guard case let .rgba(value)? = color else { return nil }
  return value
}
