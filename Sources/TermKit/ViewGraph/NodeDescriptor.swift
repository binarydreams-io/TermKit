/// Describes whether and when a node can receive focus.
public struct FocusMetadata: Equatable, Sendable {
  /// The stable focus identifier.
  public var id: FocusID?
  /// Whether the node can receive focus.
  public var isFocusable: Bool
  /// The optional explicit focus order.
  public var order: Int?

  /// Creates focus metadata.
  public init(isFocusable: Bool = false, order: Int? = nil) {
    self.id = nil
    self.isFocusable = isFocusable
    self.order = order
  }

  /// Creates focus metadata with a stable identifier.
  public init(id: FocusID, isFocusable: Bool = false, order: Int? = nil) {
    self.id = id
    self.isFocusable = isFocusable
    self.order = order
  }
}

/// Describes a node's hit-testing behavior.
public struct HitTestMetadata: Equatable, Sendable {
  /// Whether the node accepts hit tests.
  public var isEnabled: Bool
  /// The node's ordering priority during hit testing.
  public var zIndex: Int
  /// Whether the node disables hit testing for descendants.
  public var disablesDescendants: Bool
  /// The optional modal scope associated with the node.
  public var modalScope: String?

  /// Creates basic hit-test metadata.
  public init(isEnabled: Bool = false, zIndex: Int = 0) {
    self.init(
      disablesDescendants: false,
      isEnabled: isEnabled,
      zIndex: zIndex,
      modalScope: nil
    )
  }

  /// Creates hit-test metadata with descendant and modal behavior.
  public init(
    disablesDescendants: Bool,
    isEnabled: Bool = false,
    zIndex: Int = 0,
    modalScope: String? = nil
  ) {
    self.isEnabled = isEnabled
    self.zIndex = zIndex
    self.disablesDescendants = disablesDescendants
    self.modalScope = modalScope
  }
}

/// Stores callbacks for a mounted node's lifecycle.
public struct NodeLifecycle {
  /// A lifecycle callback for a mounted node.
  public typealias Handler = @MainActor (_ node: MountedNode) -> Void

  /// The callback invoked after the node mounts.
  public var onMount: Handler?
  /// The callback invoked after the node updates.
  public var onUpdate: Handler?
  /// The callback invoked after the node is removed.
  public var onRemove: Handler?

  /// Creates a set of node lifecycle callbacks.
  public init(onMount: Handler? = nil, onUpdate: Handler? = nil, onRemove: Handler? = nil) {
    self.onMount = onMount
    self.onUpdate = onUpdate
    self.onRemove = onRemove
  }
}

/// Controls how a node leaves the presentation graph.
public enum NodeRemovalPolicy: Hashable, Sendable {
  /// Detaches the node immediately.
  case immediate
  /// Retains the node until its removal transition completes.
  case retainForTransition
}

/// Defines behavior attached to a mounted node.
@MainActor
public protocol MountedNodeAttribute {
  /// The identity used to replace an existing attribute.
  var id: AnyHashable { get }
  /// The dirty flags applied when the attribute is staged.
  var stagedDirtyFlags: DirtyFlags { get }
  /// Applies the attribute and returns deferred completion actions.
  func apply(
    to node: MountedNode,
    replacing previous: (any MountedNodeAttribute)?
  ) -> [MountedNodeAttributeAction]
  /// Removes the attribute and returns deferred completion actions.
  func remove(from node: MountedNode) -> [MountedNodeAttributeAction]
  /// Samples the attribute at a time instant.
  func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample
}

/// A request for the next frame from a mounted view attribute.
struct MountedFrameDemand: Sendable, Hashable {
  /// The preferred interval between frames.
  var cadence: TimeSpan?

  /// The absolute instant for the next frame.
  var deadline: TimeInstant?

  /// Creates a mounted frame request.
  init(cadence: TimeSpan? = nil, deadline: TimeInstant? = nil) {
    if let cadence {
      precondition(cadence > .zero, "A frame cadence must be positive.")
    }
    self.cadence = cadence
    self.deadline = deadline
  }

  /// Combines two requests and keeps their earliest frame requirements.
  func merging(_ other: Self) -> Self {
    Self(
      cadence: minimum(cadence, other.cadence),
      deadline: minimum(deadline, other.deadline)
    )
  }

  private func minimum<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Value? {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)): min(lhs, rhs)
    case let (.some(lhs), .none): lhs
    case let (.none, .some(rhs)): rhs
    case (.none, .none): nil
    }
  }
}

/// A mounted attribute that requests a future runtime frame.
@MainActor
protocol MountedFrameDemandAttribute: MountedNodeAttribute {
  func frameDemand(after instant: TimeInstant) -> MountedFrameDemand?
}

/// A mounted attribute whose presentation requires declarative body evaluation.
@MainActor
protocol MountedStructureSamplingAttribute: MountedNodeAttribute {
  func requiresStructureSampling(on node: MountedNode, at instant: TimeInstant) -> Bool
}

@MainActor
protocol RuntimeShutdownAttribute: MountedNodeAttribute {
  func runtimeShutdownActions(on node: MountedNode) -> [MountedNodeAttributeAction]
}

/// An action that completes a mounted attribute update.
public typealias MountedNodeAttributeAction = @MainActor @Sendable () -> Void

/// Describes the result of sampling a mounted node attribute.
@MainActor
public struct MountedNodeAttributeSample {
  /// Whether the attribute requires further sampling.
  public var isActive: Bool
  /// The dirty flags produced by the sample.
  public var dirtyFlags: DirtyFlags
  /// Actions to run after the sample is committed.
  public var completionActions: [MountedNodeAttributeAction]

  /// Creates a mounted attribute sample.
  public init(
    isActive: Bool = false,
    dirtyFlags: DirtyFlags = [],
    completionActions: [MountedNodeAttributeAction] = []
  ) {
    self.isActive = isActive
    self.dirtyFlags = dirtyFlags
    self.completionActions = completionActions
  }

  /// A sample with no activity, invalidation, or completion actions.
  public static let inactive = MountedNodeAttributeSample()
}

extension MountedNodeAttribute {
  /// The default staged dirty flags, which contain no flags.
  public var stagedDirtyFlags: DirtyFlags {
    []
  }

  /// Returns an inactive sample by default.
  public func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample {
    .inactive
  }
}

/// Defines metadata that can copy itself for frame rollback.
@MainActor
public protocol FrameSnapshottingNodeMetadata: AnyObject {
  /// Returns an independent copy for a frame snapshot.
  func makeFrameSnapshotCopy() -> any FrameSnapshottingNodeMetadata
}

/// Describes a node before it is reconciled into a view graph.
public struct NodeDescriptor {
  /// The node's structural identity.
  public var identity: StructuralIdentity
  /// The node's semantic value.
  public var value: (any Sendable)?
  /// The primitive value used by runtime subsystems.
  public var primitive: (any Sendable)?
  /// The node's child descriptors.
  public var children: [NodeDescriptor]
  /// The node's focus metadata.
  public var focus: FocusMetadata
  /// The node's hit-test metadata.
  public var hitTest: HitTestMetadata
  /// The environment keys read by the node.
  public var environmentDependencies: Set<EnvironmentDependencyKey>
  /// The preference keys read by the node.
  public var preferenceDependencies: Set<PreferenceDependencyKey>
  /// The dirty flags applied when an existing node updates.
  public var dirtyOnUpdate: DirtyFlags
  /// The policy used when the node is removed.
  public var removalPolicy: NodeRemovalPolicy
  /// The node's lifecycle callbacks.
  public var lifecycle: NodeLifecycle
  var bodyEvaluator: (@MainActor (BodyEvaluationContext) -> [NodeDescriptor])?
  var environmentTransform: (@MainActor (inout EnvironmentValues) -> Void)?
  var effectiveEnvironment: EnvironmentValues?
  var emittedPreferences: PreferenceValues
  var resolvedPreferences: PreferenceValues
  var evaluatedDynamicPropertyValues: [Int: Any]?
  var dynamicPropertyLocations: [any DynamicPropertyLocation]
  var observationToken: ObservationToken?
  var mountedNodeAttributes: [AnyHashable: any MountedNodeAttribute]
  var expansionScope: (@MainActor (_ node: MountedNode?, _ body: @MainActor () throws -> NodeDescriptor) throws -> NodeDescriptor)?

  /// Creates a descriptor with an explicit structural identity.
  public init(
    identity: StructuralIdentity,
    value: (any Sendable)? = nil,
    primitive: (any Sendable)? = nil,
    children: [NodeDescriptor] = [],
    focus: FocusMetadata = FocusMetadata(),
    hitTest: HitTestMetadata = HitTestMetadata(),
    environmentDependencies: Set<EnvironmentDependencyKey> = [],
    preferenceDependencies: Set<PreferenceDependencyKey> = [],
    dirtyOnUpdate: DirtyFlags = .paint,
    removalPolicy: NodeRemovalPolicy = .immediate,
    lifecycle: NodeLifecycle = NodeLifecycle()
  ) {
    self.identity = identity
    self.value = value
    self.primitive = primitive
    self.children = children
    self.focus = focus
    self.hitTest = hitTest
    self.environmentDependencies = environmentDependencies
    self.preferenceDependencies = preferenceDependencies
    self.dirtyOnUpdate = dirtyOnUpdate
    self.removalPolicy = removalPolicy
    self.lifecycle = lifecycle
    self.bodyEvaluator = nil
    self.environmentTransform = nil
    self.effectiveEnvironment = nil
    self.emittedPreferences = PreferenceValues()
    self.resolvedPreferences = PreferenceValues()
    self.evaluatedDynamicPropertyValues = nil
    self.dynamicPropertyLocations = []
    self.observationToken = nil
    self.mountedNodeAttributes = [:]
    self.expansionScope = nil
  }

  /// Creates an index-based descriptor for a type.
  public init(
    type: Any.Type,
    index: Int = 0,
    branch: Int? = nil,
    value: (any Sendable)? = nil,
    primitive: (any Sendable)? = nil,
    children: [NodeDescriptor] = [],
    focus: FocusMetadata = FocusMetadata(),
    hitTest: HitTestMetadata = HitTestMetadata(),
    environmentDependencies: Set<EnvironmentDependencyKey> = [],
    preferenceDependencies: Set<PreferenceDependencyKey> = [],
    dirtyOnUpdate: DirtyFlags = .paint,
    removalPolicy: NodeRemovalPolicy = .immediate,
    lifecycle: NodeLifecycle = NodeLifecycle()
  ) {
    self.init(
      identity: StructuralIdentity(type: type, index: index, branch: branch),
      value: value,
      primitive: primitive,
      children: children,
      focus: focus,
      hitTest: hitTest,
      environmentDependencies: environmentDependencies,
      preferenceDependencies: preferenceDependencies,
      dirtyOnUpdate: dirtyOnUpdate,
      removalPolicy: removalPolicy,
      lifecycle: lifecycle
    )
  }

  /// Creates a key-based descriptor for a type.
  public init(
    type: Any.Type,
    key: some Hashable & Sendable,
    index: Int = 0,
    branch: Int? = nil,
    value: (any Sendable)? = nil,
    primitive: (any Sendable)? = nil,
    children: [NodeDescriptor] = [],
    focus: FocusMetadata = FocusMetadata(),
    hitTest: HitTestMetadata = HitTestMetadata(),
    environmentDependencies: Set<EnvironmentDependencyKey> = [],
    preferenceDependencies: Set<PreferenceDependencyKey> = [],
    dirtyOnUpdate: DirtyFlags = .paint,
    removalPolicy: NodeRemovalPolicy = .immediate,
    lifecycle: NodeLifecycle = NodeLifecycle()
  ) {
    self.init(
      identity: StructuralIdentity(type: type, key: key, index: index, branch: branch),
      value: value,
      primitive: primitive,
      children: children,
      focus: focus,
      hitTest: hitTest,
      environmentDependencies: environmentDependencies,
      preferenceDependencies: preferenceDependencies,
      dirtyOnUpdate: dirtyOnUpdate,
      removalPolicy: removalPolicy,
      lifecycle: lifecycle
    )
  }

  /// Returns the semantic value as the requested type.
  public func value<Value>(as type: Value.Type = Value.self) -> Value? {
    value as? Value
  }

  /// Returns the primitive value as the requested type.
  public func primitive<Primitive>(as type: Primitive.Type = Primitive.self) -> Primitive? {
    primitive as? Primitive
  }

  func atIndex(_ index: Int) -> NodeDescriptor {
    var copy = self
    copy.identity = identity.atIndex(index)
    return copy
  }

  func inBranch(_ branch: Int) -> NodeDescriptor {
    var copy = self
    copy.identity = identity.inBranch(branch)
    return copy
  }

  /// Creates a descriptor whose children come from a declarative view.
  @MainActor
  public static func makeDeclarative<Content: View>(_ view: Content) -> NodeDescriptor {
    var descriptor = NodeDescriptor(type: Content.self)
    descriptor.bodyEvaluator = { context in evaluateBody(view, context: context) }
    return descriptor
  }

  @MainActor
  func settingEnvironment<Key: EnvironmentKey>(_ key: Key.Type, to value: Key.Value) -> NodeDescriptor {
    var copy = self
    let previous = environmentTransform
    copy.environmentTransform = { environment in
      previous?(&environment)
      environment[key] = value
    }
    return copy
  }

  @MainActor
  func settingPreference<Key: PreferenceKey>(_ key: Key.Type, to value: Key.Value) -> NodeDescriptor {
    var copy = self
    copy.emittedPreferences[key] = value
    return copy
  }

  /// Returns a copy with the specified mounted node attribute.
  @MainActor
  public func attribute(_ attribute: any MountedNodeAttribute) -> NodeDescriptor {
    var copy = self
    copy.mountedNodeAttributes[attribute.id] = attribute
    return copy
  }

  /// Returns a descriptor whose expansion runs in a custom scope.
  @MainActor
  public func scopedExpansion(
    _ scope: @escaping @MainActor (_ node: MountedNode?, _ body: @MainActor () throws -> NodeDescriptor) throws -> NodeDescriptor
  ) -> NodeDescriptor {
    var copy = self
    copy.expansionScope = scope
    return copy
  }
}

/// Wraps a node descriptor as a declarative view.
public struct DescriptorView: View {
  /// The descriptor produced by this view.
  public let descriptor: NodeDescriptor

  /// Creates a view for a descriptor.
  public init(_ descriptor: NodeDescriptor) {
    self.descriptor = descriptor
  }

  /// The wrapped descriptor as a graph body.
  public var graphBody: [NodeDescriptor] {
    [descriptor]
  }
}
