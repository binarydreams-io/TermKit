/// Specifies whether the runtime uses motion effects.
public enum MotionPolicy: Sendable, Hashable {
  /// Enables standard motion effects.
  case standard
  /// Reduces or removes motion effects.
  case reduced

  /// A Boolean value that indicates whether animations are allowed.
  public var allowsAnimation: Bool {
    self == .standard
  }
}

/// Contains the values that a runtime view uses to produce one frame.
public struct RuntimeFrameContext: Sendable {
  /// The current terminal size in cells.
  public var terminalSize: CellSize
  /// The time instant for the frame.
  public var instant: TimeInstant
  /// The elapsed time since the previous frame.
  public var deltaTime: TimeSpan
  /// The motion policy for the frame.
  public var motionPolicy: MotionPolicy
  /// The transaction that applies to the frame.
  public var transaction: Transaction

  /// Creates a frame context.
  public init(
    terminalSize: CellSize,
    instant: TimeInstant,
    deltaTime: TimeSpan = .zero,
    motionPolicy: MotionPolicy = .standard,
    transaction: Transaction = Transaction()
  ) {
    self.terminalSize = terminalSize
    self.instant = instant
    self.deltaTime = deltaTime
    self.motionPolicy = motionPolicy
    self.transaction = transaction
  }

  /// Samples an animation at this context's time instant.
  /// - Parameters:
  ///   - animation: The animation to sample.
  ///   - start: The time instant when the animation started.
  /// - Returns: The sampled animation state.
  /// - Complexity: O(1).
  public func sample(_ animation: Animation, startedAt start: TimeInstant) -> AnimationSample {
    guard motionPolicy.allowsAnimation else {
      return animation.sample(at: animation.duration)
    }
    return animation.sample(at: start.duration(to: instant))
  }
}

/// Contains the rendered output and metadata for one runtime frame.
public struct RuntimeFrame: Sendable {
  /// The rendered terminal cells.
  public var surface: Surface
  /// The semantic tree for the rendered content.
  public var semantics: SemanticTree
  /// The optional region that changed since the previous frame.
  public var damage: DamageTracker?
  /// The optional cadence for the next frame.
  public var nextFrameCadence: TimeSpan?

  /// Creates a runtime frame.
  public init(
    surface: Surface,
    semantics: SemanticTree = SemanticTree(),
    damage: DamageTracker? = nil,
    nextFrameCadence: TimeSpan? = nil
  ) {
    if let nextFrameCadence {
      precondition(nextFrameCadence > .zero, "A frame cadence must be positive.")
    }
    self.surface = surface
    self.semantics = semantics
    self.damage = damage
    self.nextFrameCadence = nextFrameCadence
  }
}

/// Defines a view that the runtime can lay out and paint.
@MainActor
public protocol RuntimeView {
  /// Returns the node descriptor for a frame.
  func nodeDescriptor(in context: RuntimeFrameContext) -> NodeDescriptor
  /// Lays out the view graph for a frame.
  func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws
  /// Paints the view into a runtime frame.
  func paint(in context: RuntimeFrameContext, resources: inout ControlRenderResources) throws -> RuntimeFrame
}

@MainActor
protocol IncrementalRuntimeView: AnyObject, RuntimeView {
  var incrementalCounters: IncrementalRuntimeCounters { get }
  var activePresentationNodes: [MountedNode] { get }
  func beginIncrementalFrame(
    in context: RuntimeFrameContext,
    graph: ViewGraph,
    dirtyNodes: [ViewGraphFrame.DirtyNode],
    externalDamage: DamageTracker
  )
  func updatePresentation(in context: RuntimeFrameContext, graph: ViewGraph, layout: Bool) throws
  func finishIncrementalFrame()
  func rollbackIncrementalFrame()
}

struct IncrementalRuntimeCounters: Equatable {
  var layoutPassCount: Int
  var measurementCount: Int
  var paintVisitCount: Int
  var offscreenLayerCount: Int
  var offscreenCellCount: Int
}

extension RuntimeView {
  /// Applies a default layout that fills the terminal.
  /// - Complexity: O(1).
  public func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws {
    graph.root?.cache(
      size: context.terminalSize,
      frame: CellRect(origin: .zero, size: context.terminalSize)
    )
  }
}
