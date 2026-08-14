private enum OnAppearAttributeID {}
private enum ViewTaskAttributeID {}

private struct OnAppearAttribute: MountedNodeAttribute {
  let action: @MainActor @Sendable () -> Void

  var id: AnyHashable {
    ObjectIdentifier(OnAppearAttributeID.self)
  }

  func apply(
    to node: MountedNode,
    replacing previous: (any MountedNodeAttribute)?
  ) -> [MountedNodeAttributeAction] {
    guard previous == nil else { return [] }
    return [action]
  }

  func remove(from node: MountedNode) -> [MountedNodeAttributeAction] {
    []
  }
}

@MainActor
private final class MountedViewTask {
  private let action: @MainActor @Sendable () async -> Void
  private var task: Task<Void, Never>?

  init(action: @escaping @MainActor @Sendable () async -> Void) {
    self.action = action
  }

  func start() {
    guard task == nil else { return }
    task = Task { await action() }
  }

  func adopt(_ previous: MountedViewTask) {
    guard self !== previous else { return }
    task = previous.task
    previous.task = nil
    if task == nil {
      start()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  isolated deinit {
    task?.cancel()
  }
}

private struct ViewTaskAttribute: MountedNodeAttribute, RuntimeShutdownAttribute {
  let state: MountedViewTask

  var id: AnyHashable {
    ObjectIdentifier(ViewTaskAttributeID.self)
  }

  func apply(
    to node: MountedNode,
    replacing previous: (any MountedNodeAttribute)?
  ) -> [MountedNodeAttributeAction] {
    guard let previous = previous as? Self else {
      return [{ state.start() }]
    }
    return [{ state.adopt(previous.state) }]
  }

  func remove(from node: MountedNode) -> [MountedNodeAttributeAction] {
    [{ state.cancel() }]
  }

  func runtimeShutdownActions(on node: MountedNode) -> [MountedNodeAttributeAction] {
    [{ state.cancel() }]
  }
}

private struct OnAppearView<Content: View>: View {
  let content: Content
  let action: @MainActor @Sendable () -> Void

  var graphBody: [NodeDescriptor] {
    [NodeDescriptor.makeDeclarative(content).attribute(OnAppearAttribute(action: action))]
  }
}

private struct TaskView<Content: View>: View {
  let content: Content
  let action: @MainActor @Sendable () async -> Void

  var graphBody: [NodeDescriptor] {
    let state = MountedViewTask(action: action)
    return [NodeDescriptor.makeDeclarative(content).attribute(ViewTaskAttribute(state: state))]
  }
}

extension View {
  /// Adds an action that runs after this view mounts successfully.
  ///
  /// Updates to the mounted view do not run the action again.
  ///
  /// - Parameter action: The action to run on the main actor.
  /// - Complexity: O(1).
  public func onAppear(_ action: @escaping @MainActor @Sendable () -> Void) -> some View {
    OnAppearView(content: self, action: action)
  }

  /// Starts asynchronous work after this view mounts successfully.
  ///
  /// Updates do not restart the task. The graph cancels the task when it removes the view.
  ///
  /// - Parameter action: The asynchronous work to run on the main actor.
  /// - Complexity: O(1).
  public func task(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
    TaskView(content: self, action: action)
  }
}
