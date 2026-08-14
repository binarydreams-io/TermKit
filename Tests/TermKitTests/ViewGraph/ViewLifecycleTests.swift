@testable import TermKit
import Testing

@MainActor
struct ViewLifecycleTests {
  @Test
  func `onAppear runs after commit and does not repeat on update`() throws {
    let probe = ViewLifecycleProbe()
    let graph = ViewGraph()
    let view = LifecycleLeaf().onAppear { probe.appearanceCount += 1 }
    let commit = try graph.beginCommit(graph.prepare(view))

    #expect(probe.appearanceCount == 0)
    try graph.finishCommit(commit)
    #expect(probe.appearanceCount == 1)

    try graph.commit(graph.prepare(view))
    #expect(probe.appearanceCount == 1)
  }

  @Test
  func `rollback discards deferred appearance and task starts`() async throws {
    let probe = ViewLifecycleProbe()
    let graph = ViewGraph()
    let view = LifecycleLeaf()
      .onAppear { probe.appearanceCount += 1 }
      .task { probe.taskStartCount += 1 }
    let commit = try graph.beginCommit(graph.prepare(view))

    #expect(probe.appearanceCount == 0)
    #expect(probe.taskStartCount == 0)
    try graph.rollbackCommit(commit)
    await Task.yield()

    #expect(graph.root == nil)
    #expect(probe.appearanceCount == 0)
    #expect(probe.taskStartCount == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `task starts after commit, survives update, and cancels on removal`() async throws {
    let probe = ViewLifecycleProbe()
    let graph = ViewGraph()
    let view = LifecycleLeaf().task { await probe.runTask() }
    let commit = try graph.beginCommit(graph.prepare(view))

    #expect(probe.taskStartCount == 0)
    try graph.finishCommit(commit)
    await probe.waitUntilTaskStarts()
    #expect(probe.taskStartCount == 1)

    try graph.commit(graph.prepare(view))
    await Task.yield()
    #expect(probe.taskStartCount == 1)

    try graph.commit(graph.prepare(nil))
    await probe.waitUntilTaskCancels()
    #expect(probe.taskCancellationCount == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func `runtime stop cancels mounted tasks`() async throws {
    let probe = ViewLifecycleProbe()
    let runtime = Runtime(
      view: LifecycleLeaf().task { await probe.runTask() },
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 1, height: 1),
      timeSource: DeterministicTimeSource()
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    await probe.waitUntilTaskStarts()

    try runtime.stop()
    await probe.waitUntilTaskCancels()

    #expect(runtime.graph.root != nil)
    #expect(probe.taskCancellationCount == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func `task restarts when a new runtime reuses a stopped graph`() async throws {
    let probe = ViewLifecycleProbe()
    let graph = ViewGraph()
    var runtime: Runtime? = Runtime(
      view: LifecycleLeaf().task { await probe.runTask() },
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 1, height: 1),
      timeSource: DeterministicTimeSource(),
      graph: graph
    )
    try runtime?.start()
    _ = try runtime?.renderIfDue(at: .zero)
    await probe.waitUntilTaskStarts()
    try runtime?.stop()
    await probe.waitUntilTaskCancels()
    runtime = nil

    let replacement = Runtime(
      view: LifecycleLeaf().task { await probe.runTask() },
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 1, height: 1),
      timeSource: DeterministicTimeSource(),
      graph: graph
    )
    try replacement.start()
    _ = try replacement.renderIfDue(at: .zero)
    await probe.waitUntilTaskStarts(count: 2)

    #expect(probe.taskStartCount == 2)
    try replacement.stop()
  }

  @Test(.timeLimit(.minutes(1)))
  func `Dropping a graph cancels its mounted task and releases the task owner`() async throws {
    let (deallocations, deallocationContinuation) = AsyncStream.makeStream(of: Void.self)
    var deallocationIterator = deallocations.makeAsyncIterator()
    var graph: ViewGraph? = ViewGraph()
    weak var weakProbe: ViewLifecycleProbe?

    do {
      let probe = ViewLifecycleProbe {
        _ = deallocationContinuation.yield(())
        deallocationContinuation.finish()
      }
      weakProbe = probe
      let mountedGraph = try #require(graph)
      try mountedGraph.commit(
        mountedGraph.prepare(LifecycleLeaf().task { await probe.runTask() })
      )
      await probe.waitUntilTaskStarts()
    }

    #expect(weakProbe != nil)
    graph = nil
    await weakProbe?.waitUntilTaskCancels()
    _ = await deallocationIterator.next()

    #expect(weakProbe == nil)
  }
}

@MainActor
private struct LifecycleLeaf: View {
  var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self)]
  }
}

@MainActor
private final class ViewLifecycleProbe {
  var appearanceCount = 0
  var taskStartCount = 0
  var taskCancellationCount = 0

  private let deinitHandler: (@MainActor @Sendable () -> Void)?
  private var taskStartContinuation: CheckedContinuation<Void, Never>?
  private var taskStartTarget = 1
  private var taskCancellationContinuation: CheckedContinuation<Void, Never>?

  init(deinitHandler: (@MainActor @Sendable () -> Void)? = nil) {
    self.deinitHandler = deinitHandler
  }

  isolated deinit {
    deinitHandler?()
  }

  func runTask() async {
    taskStartCount += 1
    if taskStartCount >= taskStartTarget {
      let startContinuation = taskStartContinuation
      taskStartContinuation = nil
      startContinuation?.resume()
    }

    do {
      try await Task.sleep(for: .seconds(60))
    } catch {
      guard Task.isCancelled else { return }
      taskCancellationCount += 1
      let cancellationContinuation = taskCancellationContinuation
      taskCancellationContinuation = nil
      cancellationContinuation?.resume()
    }
  }

  func waitUntilTaskStarts(count expectedCount: Int = 1) async {
    guard taskStartCount < expectedCount else { return }
    await withCheckedContinuation { continuation in
      taskStartTarget = expectedCount
      taskStartContinuation = continuation
    }
  }

  func waitUntilTaskCancels() async {
    guard taskCancellationCount == 0 else { return }
    await withCheckedContinuation { continuation in
      taskCancellationContinuation = continuation
    }
  }
}
