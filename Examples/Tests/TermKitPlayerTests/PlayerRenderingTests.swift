import Foundation
import TermKit
@testable import TermKitPlayer
import Testing

@MainActor
struct PlayerRenderingTests {
  @Test
  func `Player decodes and renders its original PNG and JPEG artwork`() throws {
    let artwork = try loadPlayerArtwork()
    #expect(artwork.png.width == 96)
    #expect(artwork.png.height == 96)
    #expect(artwork.jpeg.width == 96)
    #expect(artwork.jpeg.height == 96)
  }

  @Test
  func `Paused player is idle and playing player requests timeline frames`() throws {
    let artwork = try loadPlayerArtwork()
    let model = PlayerModel(timeSource: DeterministicTimeSource())
    let paused = try render(model: model, artwork: artwork, size: CellSize(width: 120, height: 32))
    #expect(paused.runtime.nextDeadline(at: .zero) == nil)

    model.play()
    paused.runtime.invalidate()
    let instant = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try paused.runtime.renderIfDue(at: instant)
    #expect(paused.runtime.nextDeadline(at: instant) == instant.advanced(by: .milliseconds(80)))

    model.pause()
    paused.runtime.invalidate()
    let finalInstant = instant.advanced(by: FrameScheduler.minimumFrameInterval)
    _ = try paused.runtime.renderIfDue(at: finalInstant)
    #expect(paused.runtime.nextDeadline(at: finalInstant) == nil)
  }

  @Test
  func `Spectrum uses cyan data cells and red peak cells`() throws {
    var surface = Surface(size: CellSize(width: 16, height: 1))
    var resources = ControlRenderResources(colorCapability: .trueColor)
    _ = try SpectrumView(instant: .zero, isActive: false).paint(
      into: &surface,
      context: PaintContext(clip: surface.bounds),
      resources: &resources
    )
    let styles = surface.cells.compactMap { resources.styles.value(for: $0.styleID) }

    #expect(styles.contains(PlayerStyles.data))
    #expect(styles.contains(PlayerStyles.peakData))
  }

  @Test(
    arguments: [
      (40, 16), (80, 24), (120, 32), (180, 40)
    ]
  )
  func `Canonical player layouts match semantic snapshots`(width: Int, height: Int) throws {
    let model = PlayerModel(timeSource: DeterministicTimeSource())
    let output = try render(
      model: model,
      artwork: loadPlayerArtwork(),
      size: CellSize(width: width, height: height)
    )
    let snapshot = try playerSnapshot(
      surface: #require(output.presenter.frontSurface),
      resources: output.presenter.resources,
      semantics: output.frame.semantics
    )
    let name = "player-\(width).snap"
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Snapshots")
      .appendingPathComponent(name)
    if ProcessInfo.processInfo.environment["TERMKIT_RECORD_SNAPSHOTS"] == "1" {
      try snapshot.write(to: source, atomically: true, encoding: .utf8)
    }
    let expected = try String(contentsOf: source, encoding: .utf8)
    #expect(snapshot == expected)
  }

  private func render(
    model: PlayerModel,
    artwork: PlayerArtwork,
    size: CellSize
  ) throws -> (runtime: Runtime, presenter: FramePresenter, frame: RuntimeFrameResult) {
    let presenter = FramePresenter(session: PlayerTestSession())
    let runtime = Runtime(
      view: PlayerView(model: model, artwork: artwork),
      presenter: presenter,
      terminalSize: size,
      timeSource: DeterministicTimeSource()
    )
    try runtime.start()
    let frame = try #require(try runtime.renderIfDue(at: .zero))
    return (runtime, presenter, frame)
  }
}

private final class PlayerTestSession: RuntimeTerminalSession {
  private(set) var state = TerminalSessionState.inactive
  let capabilities = TerminalCapabilities(color: .trueColor, synchronizedOutput: .unsupported)

  func start() throws -> TerminalSessionTransition {
    state = .active
    return .started
  }

  func suspend() throws -> TerminalSessionTransition {
    state = .suspended
    return .suspended
  }

  func resume() throws -> TerminalSessionTransition {
    state = .active
    return .resumed(requiresFullRepaint: true)
  }

  func stop() throws -> TerminalSessionTransition {
    state = .inactive
    return .stopped
  }

  func present(_ bytes: [UInt8]) throws {}
  func writeCapabilityQuery(_ bytes: [UInt8]) throws {}
  func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {}
  func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
    .terminate
  }

  func readInput(maximumByteCount: Int) throws -> [UInt8] {
    []
  }

  func readTerminalSize() throws -> TerminalSize {
    TerminalSize(columns: 1, rows: 1)
  }
}

private func playerSnapshot(
  surface: Surface,
  resources: ControlRenderResources,
  semantics: SemanticTree
) -> String {
  let rows = (0 ..< surface.size.height).map { y in
    (0 ..< surface.size.width).compactMap { x -> String? in
      let cell = surface[CellPoint(x: x, y: y)]
      guard cell.isContinuation == false else { return nil }
      return resources.graphemes.value(for: cell.graphemeID) ?? " "
    }.joined().trimmingCharacters(in: .whitespaces)
  }
  let visibleRows = rows.enumerated().filter { $0.element.isEmpty == false }
    .map { "row \($0.offset): \($0.element)" }
  let nodes = semantics.roots.flatMap(flatten).map { node in
    let frame = node.frame.map { "\($0.minX),\($0.minY),\($0.size.width),\($0.size.height)" } ?? "nil"
    let actions = node.actions.map(\.rawValue).sorted().joined(separator: ",")
    return "node \(node.id.rawValue) role=\(node.role.rawValue) label=\(node.label) "
      + "value=\(node.value ?? "nil") frame=\(frame) actions=\(actions)"
  }
  return
    (["termkit-player-semantic-snapshot-v1", "size \(surface.size.width)x\(surface.size.height)"]
      + visibleRows + nodes).joined(separator: "\n") + "\n"
}

private func flatten(_ node: SemanticNode) -> [SemanticNode] {
  [node] + node.children.flatMap(flatten)
}
