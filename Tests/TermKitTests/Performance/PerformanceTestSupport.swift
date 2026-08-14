import Foundation
@testable import TermKit

let termKitPerformanceTestsEnabled =
  ProcessInfo.processInfo.environment["TERMKIT_RUN_PERFORMANCE_TESTS"] == "1"

func measureBenchmark<Output>(
  name: String,
  warmupCount: Int,
  sampleCount: Int,
  iterationsPerSample: Int = 1,
  operation: (Int) throws -> Output,
  inspect: (Output) -> Void = { _ in }
) rethrows -> BenchmarkResult {
  precondition(warmupCount >= 0)
  precondition(sampleCount > 0)
  precondition(iterationsPerSample > 0)

  for index in 0 ..< warmupCount {
    try inspect(operation(index))
  }

  let clock = ContinuousClock()
  var samples: [Int64] = []
  samples.reserveCapacity(sampleCount)
  for index in 0 ..< sampleCount {
    let start = clock.now
    let output = try operation(warmupCount + index)
    let elapsed = start.duration(to: clock.now)
    samples.append(nanoseconds(in: elapsed))
    inspect(output)
  }

  return BenchmarkResult(
    name: name,
    samplesNanoseconds: samples,
    warmupCount: warmupCount,
    iterationsPerSample: iterationsPerSample
  )
}

private func nanoseconds(in duration: Duration) -> Int64 {
  let components = duration.components
  let (wholeSeconds, secondsOverflow) = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
  precondition(secondsOverflow == false, "Benchmark duration exceeds Int64 range.")
  let fractional = components.attoseconds / 1_000_000_000
  let (result, additionOverflow) = wholeSeconds.addingReportingOverflow(fractional)
  precondition(additionOverflow == false, "Benchmark duration exceeds Int64 range.")
  return result
}

@MainActor
final class RuntimeFrameHarness {
  let size: CellSize
  let session: BenchmarkTerminalSession
  let view: BenchmarkRuntimeView
  let runtime: Runtime
  private(set) var instant = TimeInstant.zero

  init(size: CellSize) throws {
    self.size = size
    self.session = BenchmarkTerminalSession()
    let presenter = FramePresenter(session: session)
    self.view = try BenchmarkRuntimeView(size: size, presenter: presenter)
    self.runtime = Runtime(
      view: view,
      presenter: presenter,
      terminalSize: size,
      timeSource: DeterministicTimeSource()
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: instant)
    session.resetCounters()
    view.resetCounters()
  }

  func localizedFrame(index: Int, rect: CellRect) throws -> RuntimeFrameResult {
    view.prepareLocalizedFrame(index: index, rect: rect)
    runtime.invalidate(
      .region(rect),
      transaction: Transaction(animation: .linear(duration: .milliseconds(100)))
    )
    return try renderNextFrame()
  }

  func fullRepaintFrame(index: Int) throws -> RuntimeFrameResult {
    view.prepareFullRepaint(index: index)
    runtime.invalidate(.all)
    return try renderNextFrame()
  }

  func renderNextFrame() throws -> RuntimeFrameResult {
    instant = instant.advanced(by: FrameScheduler.minimumFrameInterval)
    guard let result = try runtime.renderIfDue(at: instant) else {
      preconditionFailure("A requested benchmark frame was not due.")
    }
    return result
  }
}

@MainActor
final class BenchmarkRuntimeView: RuntimeView {
  private(set) var layoutCount = 0
  private(set) var paintCount = 0
  private(set) var descriptorCount = 0
  private(set) var animatedPaintCount = 0
  private var surface: Surface
  private var damage: DamageTracker?
  private let primaryGrapheme: GraphemeID
  private let alternateGrapheme: GraphemeID
  private var revision = 0

  init(size: CellSize, presenter: FramePresenter) throws {
    self.primaryGrapheme = try presenter.withRenderResources { try $0.graphemes.intern("a") }
    self.alternateGrapheme = try presenter.withRenderResources { try $0.graphemes.intern("b") }
    self.surface = Surface(
      size: size,
      fill: PackedCell(graphemeID: primaryGrapheme, styleID: .default, displayWidth: 1)
    )
  }

  func resetCounters() {
    layoutCount = 0
    paintCount = 0
    descriptorCount = 0
    animatedPaintCount = 0
  }

  func prepareLocalizedFrame(index: Int, rect: CellRect) {
    revision = index
    let identifier = index.isMultiple(of: 2) ? alternateGrapheme : primaryGrapheme
    paint(identifier, in: rect)
    var tracker = DamageTracker(bounds: surface.bounds)
    tracker.add(rect)
    damage = tracker
  }

  func prepareFullRepaint(index: Int) {
    revision = index
    let identifier = index.isMultiple(of: 2) ? alternateGrapheme : primaryGrapheme
    surface = Surface(
      size: surface.size,
      fill: PackedCell(graphemeID: identifier, styleID: .default, displayWidth: 1)
    )
    damage = nil
  }

  func nodeDescriptor(in context: RuntimeFrameContext) -> NodeDescriptor {
    descriptorCount += 1
    return NodeDescriptor(type: BenchmarkRuntimeView.self, value: revision, dirtyOnUpdate: .layout)
  }

  func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws {
    layoutCount += 1
    graph.root?.cache(
      size: context.terminalSize,
      frame: CellRect(origin: .zero, size: context.terminalSize)
    )
  }

  func paint(
    in context: RuntimeFrameContext,
    resources: inout ControlRenderResources
  ) throws -> RuntimeFrame {
    paintCount += 1
    if context.transaction.animation != nil {
      animatedPaintCount += 1
    }
    defer { damage = nil }
    return RuntimeFrame(surface: surface, damage: damage)
  }

  private func paint(_ identifier: GraphemeID, in rect: CellRect) {
    guard let clipped = surface.bounds.intersection(rect) else { return }
    for y in clipped.minY ..< clipped.maxY {
      for x in clipped.minX ..< clipped.maxX {
        do {
          try surface.write(graphemeID: identifier, at: CellPoint(x: x, y: y))
        } catch {
          preconditionFailure("Benchmark coordinates must be valid: \(error)")
        }
      }
    }
  }
}

final class BenchmarkTerminalSession: RuntimeTerminalSession {
  private(set) var state: TerminalSessionState = .inactive
  private(set) var logicalWriteCount = 0
  private(set) var presentedByteCount = 0
  let capabilities = TerminalCapabilities(color: .trueColor, synchronizedOutput: .unsupported)

  func resetCounters() {
    logicalWriteCount = 0
    presentedByteCount = 0
  }

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

  func present(_ bytes: [UInt8]) throws {
    logicalWriteCount += 1
    presentedByteCount += bytes.count
  }

  func writeCapabilityQuery(_ bytes: [UInt8]) throws {}

  func applySynchronizedOutputProbeResult(_ result: SynchronizedOutputProbeResult) {}

  func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
    switch event {
    case .interrupt, .terminate, .quit, .hangup:
      state = .inactive
      return .terminate
    case .suspend:
      state = .suspended
      return .suspendProcess
    case .resume:
      state = .active
      return .resumed(requiresFullRepaint: true)
    case .windowChanged:
      return .readSize
    }
  }

  func readInput(maximumByteCount: Int) throws -> [UInt8] {
    []
  }

  func readTerminalSize() throws -> TerminalSize {
    TerminalSize(columns: 1, rows: 1)
  }
}
