import Observation
@testable import TermKit
import Testing

@MainActor
struct InputInvalidationRuntimeTests {
  @Test
  func `State-driven input renders no frame for an event that changes nothing`() throws {
    let session = FakeTerminalSession()
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text("idle"),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      inputInvalidation: .stateDriven
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    let payloadCount = session.presentedPayloads.count

    try runtime.process(.input(.key(TerminalKeyEvent(key: .down))))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

    #expect(session.presentedPayloads.count == payloadCount)
  }

  @Test(.timeLimit(.minutes(1)))
  func `State-driven input renders the observed mutation`() async throws {
    let model = InputCounterModel()
    let session = FakeTerminalSession()
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: InputCounterView(model: model),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      onInput: { _ in model.value += 1 },
      inputInvalidation: .stateDriven
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    #expect(surfaceLine(presenter) == "v0")
    let (invalidations, continuation) = AsyncStream.makeStream(of: Void.self)
    var iterator = invalidations.makeAsyncIterator()
    runtime.graph.invalidationHandler = { _, _ in
      _ = continuation.yield(())
    }
    defer { continuation.finish() }

    try runtime.process(.input(.key(TerminalKeyEvent(key: .enter))))
    _ = await iterator.next()
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

    #expect(surfaceLine(presenter) == "v1")
  }

  @Test
  func `State-driven selection still repaints the highlight`() throws {
    let session = FakeTerminalSession()
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text("select"),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration(copiesOnRelease: false),
      inputInvalidation: .stateDriven
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(.input(.mouse(TerminalMouseEvent(
      action: .press(.left), position: TerminalCellPoint(column: 0, row: 0)
    ))))
    try runtime.process(.input(.mouse(TerminalMouseEvent(
      action: .drag(.left), position: TerminalCellPoint(column: 2, row: 0)
    ))))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

    let surface = try #require(presenter.frontSurface)
    #expect(
      presenter.resources.styles.value(for: surface[.zero].styleID)?
        .attributes.contains(.inverse) == true
    )
  }

  private func surfaceLine(_ presenter: FramePresenter) -> String {
    guard let surface = presenter.frontSurface else { return "" }
    return (0 ..< surface.size.width).compactMap { x -> String? in
      let cell = surface[CellPoint(x: x, y: 0)]
      guard cell.isContinuation == false else { return nil }
      return presenter.resources.graphemes.value(for: cell.graphemeID)
    }.joined().trimmingCharacters(in: .whitespaces)
  }
}

@MainActor
@Observable
private final class InputCounterModel {
  var value = 0
}

@MainActor
private struct InputCounterView: View {
  let model: InputCounterModel

  var graphBody: [NodeDescriptor] {
    Text("v\(model.value)").graphBody
  }
}
