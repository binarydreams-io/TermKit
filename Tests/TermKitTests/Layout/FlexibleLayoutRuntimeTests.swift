@testable import TermKit
import Testing

@MainActor
struct FlexibleLayoutRuntimeTests {
  @Test
  func `Horizontal spacer places text at the leading and trailing edges`() throws {
    let (runtime, presenter) = makeRuntime(
      HStack {
        Text("L", id: "leading")
        Spacer()
        Text("R", id: "trailing")
      },
      size: CellSize(width: 10, height: 1)
    )
    try runtime.start()

    let frame = try #require(try runtime.renderIfDue(at: .zero))

    #expect(grapheme(at: CellPoint(x: 0), presenter: presenter) == "L")
    #expect(grapheme(at: CellPoint(x: 9), presenter: presenter) == "R")
    #expect(frame.semantics.roots.map(\.id) == ["leading", "trailing"])
    #expect(spacerFrames(in: runtime.graph) == [CellRect(x: 1, y: 0, width: 8, height: 1)])
  }

  @Test
  func `Multiple spacers honor minimum lengths and split the remainder in source order`() throws {
    let (runtime, presenter) = makeRuntime(
      HStack {
        Text("A")
        Spacer(minLength: 2)
        Text("B")
        Spacer(minLength: 1)
        Text("C")
      },
      size: CellSize(width: 15, height: 1)
    )
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    #expect(grapheme(at: CellPoint(x: 0), presenter: presenter) == "A")
    #expect(grapheme(at: CellPoint(x: 8), presenter: presenter) == "B")
    #expect(grapheme(at: CellPoint(x: 14), presenter: presenter) == "C")
    #expect(spacerFrames(in: runtime.graph).map(\.width) == [7, 5])
  }

  @Test
  func `Vertical spacer places text at the top and bottom edges`() throws {
    let (runtime, presenter) = makeRuntime(
      VStack {
        Text("T")
        Spacer(minLength: 1)
        Text("B")
      },
      size: CellSize(width: 1, height: 5)
    )
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    #expect(grapheme(at: CellPoint(x: 0, y: 0), presenter: presenter) == "T")
    #expect(grapheme(at: CellPoint(x: 0, y: 4), presenter: presenter) == "B")
    #expect(spacerFrames(in: runtime.graph) == [CellRect(x: 0, y: 1, width: 1, height: 3)])
  }

  @Test
  func `Geometry reader rebuilds graph body for 60 and 120 column viewports`() throws {
    let (runtime, presenter) = makeRuntime(
      GeometryReader { context in
        if context.size.width >= 120 {
          Text("wide", id: "mode")
        } else {
          Text("compact", id: "mode")
        }
      },
      size: CellSize(width: 60, height: 1)
    )
    try runtime.start()

    let compact = try #require(try runtime.renderIfDue(at: .zero))
    #expect(compact.semantics.node(withID: "mode")?.label == "compact")
    #expect(surfaceText(presenter).hasPrefix("compact"))

    try runtime.process(.resize(CellSize(width: 120, height: 1)))
    let wide = try #require(
      try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    )

    #expect(wide.semantics.node(withID: "mode")?.label == "wide")
    #expect(surfaceText(presenter).hasPrefix("wide"))
  }

  @Test
  func `Geometry reader receives a nested frame proposal`() throws {
    let (runtime, presenter) = makeRuntime(
      GeometryReader { context in
        Text("\(context.size.width)")
      }
      .frame(width: 20),
      size: CellSize(width: 120, height: 1)
    )
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)

    #expect(surfaceText(presenter).contains("20"))
  }

  private func makeRuntime(
    _ view: some View,
    size: CellSize
  ) -> (runtime: Runtime, presenter: FramePresenter) {
    let presenter = FramePresenter(session: FakeTerminalSession())
    let runtime = Runtime(
      view: view,
      presenter: presenter,
      terminalSize: size,
      timeSource: DeterministicTimeSource()
    )
    return (runtime, presenter)
  }

  private func spacerFrames(in graph: ViewGraph) -> [CellRect] {
    descendants(of: graph.root)
      .filter { $0.value(as: SpacerLayoutValue.self) != nil }
      .compactMap(\.cachedFrame)
      .sorted {
        ($0.minY, $0.minX) < ($1.minY, $1.minX)
      }
  }

  private func descendants(of root: MountedNode?) -> [MountedNode] {
    guard let root else { return [] }
    return [root] + root.children.flatMap { descendants(of: $0) }
  }

  private func grapheme(at point: CellPoint, presenter: FramePresenter) -> String? {
    guard let surface = presenter.frontSurface else { return nil }
    return presenter.resources.graphemes.value(for: surface[point].graphemeID)
  }

  private func surfaceText(_ presenter: FramePresenter) -> String {
    guard let surface = presenter.frontSurface else { return "" }
    return (0 ..< surface.size.height).map { y in
      (0 ..< surface.size.width).compactMap { x in
        let cell = surface[CellPoint(x: x, y: y)]
        guard cell.isContinuation == false else { return nil }
        return presenter.resources.graphemes.value(for: cell.graphemeID)
      }.joined()
    }.joined(separator: "\n")
  }
}
