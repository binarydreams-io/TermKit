/// Identifies a mounted node's presentation state.
public enum NodePresentationPhase: Sendable, Hashable {
  /// The node is entering the presentation.
  case inserting
  /// The node is active in the presentation.
  case active
  /// The node is leaving the presentation.
  case removing
}

/// Identifies one presentation transition for a node.
public struct PresentationTransitionToken: Sendable, Hashable {
  /// The transitioning node's identifier.
  public let nodeID: NodeID
  /// The node's transition epoch.
  public let epoch: UInt64

  /// Creates a presentation transition token.
  public init(nodeID: NodeID, epoch: UInt64) {
    self.nodeID = nodeID
    self.epoch = epoch
  }
}

/// Records a removed node's position among presented siblings.
public struct PresentationPlacement: Sendable, Hashable {
  /// The identifier of the presentation parent.
  public let parentID: NodeID?
  /// The node's former sibling index.
  public let siblingIndex: Int
  /// The identifier of the former previous sibling.
  public let previousSiblingID: NodeID?
  /// The identifier of the former next sibling.
  public let nextSiblingID: NodeID?

  /// Creates a presentation placement.
  public init(
    parentID: NodeID?,
    siblingIndex: Int,
    previousSiblingID: NodeID?,
    nextSiblingID: NodeID?
  ) {
    self.parentID = parentID
    self.siblingIndex = siblingIndex
    self.previousSiblingID = previousSiblingID
    self.nextSiblingID = nextSiblingID
  }
}

/// Describes invalidated work for a mounted node.
public struct DirtyFlags: OptionSet, Hashable, Sendable {
  /// The normalized bit representation of the flags.
  public let rawValue: UInt8

  /// Creates and normalizes dirty flags from raw bits.
  public init(rawValue: UInt8) {
    if rawValue & 0b100 != 0 {
      self.rawValue = 0b111
    } else if rawValue & 0b010 != 0 {
      self.rawValue = 0b011
    } else {
      self.rawValue = rawValue & 0b001
    }
  }

  /// Marks paint output as invalid.
  public static let paint = DirtyFlags(rawValue: 0b001)
  /// Marks layout and paint output as invalid.
  public static let layout = DirtyFlags(rawValue: 0b010)
  /// Marks structure, layout, and paint output as invalid.
  public static let structure = DirtyFlags(rawValue: 0b100)
}

/// Represents a reconciled node in a view graph.
@MainActor
public final class MountedNode: Identifiable {
  struct Snapshot {
    let identity: StructuralIdentity
    let parent: MountedNode?
    let children: [MountedNode]
    let value: (any Sendable)?
    let primitive: (any Sendable)?
    let focusMetadata: FocusMetadata
    let hitTestMetadata: HitTestMetadata
    let environmentDependencies: Set<EnvironmentDependencyKey>
    let environment: EnvironmentValues
    let preferenceDependencies: Set<PreferenceDependencyKey>
    let cachedSize: CellSize?
    let cachedFrame: CellRect?
    let paintBounds: CellRect
    let localDirtyFlags: DirtyFlags
    let dirtyFlags: DirtyFlags
    let dirtyGeneration: UInt64
    let layoutGeneration: UInt64
    let isPresentationOnly: Bool
    let presentationPhase: NodePresentationPhase
    let presentationEpoch: UInt64
    let presentationPlacement: PresentationPlacement?
    let lifecycle: NodeLifecycle
    let removalPolicy: NodeRemovalPolicy
    let presentationParentID: NodeID?
    fileprivate let stateSlots: [StateSlotID: Any]
    fileprivate let dynamicPropertyValues: [Int: Any]
    fileprivate let metadataSlots: [ObjectIdentifier: Any]
    fileprivate let preferenceValues: PreferenceValues
    fileprivate let observationToken: ObservationToken?
    fileprivate let mountedNodeAttributes: [AnyHashable: any MountedNodeAttribute]
  }

  /// The node's stable identifier within its graph.
  public let id: NodeID
  /// The node's current structural identity.
  public internal(set) var identity: StructuralIdentity
  /// The node's parent, if it is not a root.
  public internal(set) weak var parent: MountedNode?
  /// The node's active or retained children.
  public internal(set) var children: [MountedNode]
  /// The node's semantic value.
  public internal(set) var value: (any Sendable)?
  /// The node's primitive runtime value.
  public internal(set) var primitive: (any Sendable)?
  /// The node's focus metadata.
  public internal(set) var focusMetadata: FocusMetadata
  /// The node's hit-test metadata.
  public internal(set) var hitTestMetadata: HitTestMetadata
  /// The environment keys read by the node.
  public internal(set) var environmentDependencies: Set<EnvironmentDependencyKey>
  var environment: EnvironmentValues
  /// The preference keys read by the node.
  public internal(set) var preferenceDependencies: Set<PreferenceDependencyKey>
  /// The most recently cached measured size.
  public internal(set) var cachedSize: CellSize?
  /// The most recently cached layout frame.
  public internal(set) var cachedFrame: CellRect?
  /// The region that can contain painted output.
  public internal(set) var paintBounds: CellRect
  /// The dirty flags produced directly by this node.
  public internal(set) var localDirtyFlags: DirtyFlags
  /// The dirty flags aggregated from this node and its descendants.
  public internal(set) var dirtyFlags: DirtyFlags
  /// A counter that changes when dirty state is marked.
  public internal(set) var dirtyGeneration: UInt64
  /// A counter that changes when layout is invalidated.
  public internal(set) var layoutGeneration: UInt64
  /// Whether the node exists only for retained presentation.
  public internal(set) var isPresentationOnly: Bool
  /// The node's current presentation phase.
  public internal(set) var presentationPhase: NodePresentationPhase
  /// The node's retained presentation placement.
  public internal(set) var presentationPlacement: PresentationPlacement?

  var lifecycle: NodeLifecycle
  var removalPolicy: NodeRemovalPolicy
  var presentationParentID: NodeID?
  private var presentationEpoch: UInt64
  weak var graph: ViewGraph?
  private var stateSlots: [StateSlotID: Any]
  var dynamicPropertyValues: [Int: Any]
  private var metadataSlots: [ObjectIdentifier: Any]
  /// The preference values resolved from this node and its descendants.
  public internal(set) var preferenceValues: PreferenceValues
  private var observationToken: ObservationToken?
  var mountedNodeAttributes: [AnyHashable: any MountedNodeAttribute]

  init(id: NodeID, descriptor: NodeDescriptor, graph: ViewGraph) {
    self.id = id
    self.identity = descriptor.identity
    self.children = []
    self.value = descriptor.value
    self.primitive = descriptor.primitive
    self.focusMetadata = descriptor.focus
    self.hitTestMetadata = descriptor.hitTest
    self.environmentDependencies = descriptor.environmentDependencies
    self.environment = descriptor.effectiveEnvironment ?? EnvironmentValues()
    self.preferenceDependencies = descriptor.preferenceDependencies
    self.cachedSize = nil
    self.cachedFrame = nil
    self.paintBounds = .zero
    self.localDirtyFlags = .structure
    self.dirtyFlags = .structure
    self.dirtyGeneration = 1
    self.layoutGeneration = 0
    self.isPresentationOnly = false
    self.presentationPhase = .active
    self.presentationPlacement = nil
    self.lifecycle = descriptor.lifecycle
    self.removalPolicy = descriptor.removalPolicy
    self.presentationParentID = nil
    self.presentationEpoch = 0
    self.graph = graph
    self.stateSlots = [:]
    self.dynamicPropertyValues = [:]
    self.metadataSlots = [:]
    self.preferenceValues = PreferenceValues()
    self.observationToken = nil
    self.mountedNodeAttributes = descriptor.mountedNodeAttributes
    applyDeclarativeStorage(descriptor)
  }

  /// Whether the node can receive focus in its current ancestry.
  ///
  /// - Complexity: O(*h*), where *h* is the node's ancestor count.
  public var isFocusable: Bool {
    isPresentationOnly == false
      && focusMetadata.isFocusable
      && ancestorsDisableHitTesting == false
  }

  /// Whether the node accepts hit tests in its current ancestry.
  ///
  /// - Complexity: O(*h*), where *h* is the node's ancestor count.
  public var acceptsHitTesting: Bool {
    isPresentationOnly == false
      && hitTestMetadata.isEnabled
      && ancestorsDisableHitTesting == false
  }

  /// Whether the node can receive focus or accept hit tests.
  ///
  /// - Complexity: O(*h*), where *h* is the node's ancestor count.
  public var isInteractive: Bool {
    isFocusable || acceptsHitTesting
  }

  /// The nearest modal scope in the node's ancestry.
  ///
  /// - Complexity: O(*h*), where *h* is the node's ancestor count.
  public var activeModalScope: String? {
    sequence(first: self, next: \.parent).compactMap(\.hitTestMetadata.modalScope).first
  }

  private var ancestorsDisableHitTesting: Bool {
    guard let parent else { return false }
    return sequence(first: parent, next: \.parent).contains { $0.hitTestMetadata.disablesDescendants }
  }

  /// Returns the semantic value as the requested type.
  public func value<Value>(as type: Value.Type = Value.self) -> Value? {
    value as? Value
  }

  /// Returns the primitive value as the requested type.
  public func primitive<Primitive>(as type: Primitive.Type = Primitive.self) -> Primitive? {
    primitive as? Primitive
  }

  /// Returns the stored value for a state key.
  public func state<Value>(for key: StateKey<Value>) -> Value? {
    stateSlots[StateSlotID(key)] as? Value
  }

  /// Returns stored state or creates and stores a default value.
  @discardableResult
  public func state<Value>(for key: StateKey<Value>, default makeValue: @autoclosure () -> Value) -> Value {
    if let value = state(for: key) {
      return value
    }
    let value = makeValue()
    stateSlots[StateSlotID(key)] = value
    return value
  }

  /// Stores a value for a state key and invalidates structure.
  public func setState<Value>(_ value: Value, for key: StateKey<Value>) {
    stateSlots[StateSlotID(key)] = value
    invalidate(.structure)
  }

  /// Removes a state value and invalidates structure when it existed.
  public func removeState(for key: StateKey<some Any>) {
    guard stateSlots.removeValue(forKey: StateSlotID(key)) != nil else { return }
    invalidate(.structure)
  }

  /// Returns metadata associated with a metadata key.
  public func metadata<Key: NodeMetadataKey>(for key: Key.Type) -> Key.Value? {
    metadataSlots[ObjectIdentifier(key)] as? Key.Value
  }

  /// Stores or removes metadata associated with a metadata key.
  public func setMetadata<Key: NodeMetadataKey>(_ value: Key.Value?, for key: Key.Type) {
    metadataSlots[ObjectIdentifier(key)] = value
  }

  /// Returns the resolved value for a preference key.
  public func preference<Key: PreferenceKey>(_ key: Key.Type) -> Key.Value {
    preferenceValues.value(for: key)
  }

  /// Caches the node's measured size, frame, and paint bounds.
  public func cache(size: CellSize, frame: CellRect, paintBounds: CellRect? = nil) {
    cachedSize = size
    cachedFrame = frame
    self.paintBounds = paintBounds ?? frame
  }

  /// Invalidates the node with the specified dirty flags.
  public func invalidate(_ flags: DirtyFlags) {
    graph?.invalidate(self, flags: flags)
  }

  /// Clears dirty flags produced by and aggregated into this node.
  public func clearDirtyFlags() {
    localDirtyFlags = []
    dirtyFlags = []
  }

  /// Completes the node's current presentation transition.
  @discardableResult
  public func completePresentationTransition() -> Bool {
    completePresentationTransition(currentPresentationTransitionToken)
  }

  /// Completes the presentation transition if the token is current.
  @discardableResult
  public func completePresentationTransition(_ token: PresentationTransitionToken) -> Bool {
    graph?.completeTransition(for: id, token: token) ?? false
  }

  /// A token for the node's current presentation transition epoch.
  public var currentPresentationTransitionToken: PresentationTransitionToken {
    PresentationTransitionToken(nodeID: id, epoch: presentationEpoch)
  }

  /// Starts an insertion or removal presentation transition.
  @discardableResult
  public func beginPresentationTransition(_ phase: NodePresentationPhase) -> PresentationTransitionToken {
    precondition(phase != .active, "A presentation transition phase must be insertion or removal.")
    presentationEpoch &+= 1
    presentationPhase = phase
    markDirty(.paint)
    return currentPresentationTransitionToken
  }

  func apply(_ descriptor: NodeDescriptor) {
    identity = descriptor.identity
    value = descriptor.value
    primitive = descriptor.primitive
    focusMetadata = descriptor.focus
    hitTestMetadata = descriptor.hitTest
    environmentDependencies = descriptor.environmentDependencies
    environment = descriptor.effectiveEnvironment ?? EnvironmentValues()
    preferenceDependencies = descriptor.preferenceDependencies
    lifecycle = descriptor.lifecycle
    removalPolicy = descriptor.removalPolicy
    presentationParentID = nil
    presentationPlacement = nil
    isPresentationOnly = false
    mountedNodeAttributes = descriptor.mountedNodeAttributes
    applyDeclarativeStorage(descriptor)
  }

  func markDirty(_ flags: DirtyFlags) {
    localDirtyFlags.formUnion(flags)
    markAggregateDirty(flags)
  }

  func markAggregateDirty(_ flags: DirtyFlags) {
    dirtyFlags.formUnion(flags)
    dirtyGeneration &+= 1
    if flags.contains(.layout) {
      layoutGeneration &+= 1
    }
  }

  func markPresentationOnly() {
    isPresentationOnly = true
    markDirty(.paint)
    for child in children {
      child.markPresentationOnly()
    }
  }

  func prepareForRemoval(placement: PresentationPlacement) {
    presentationPlacement = placement
    _ = beginPresentationTransition(.removing)
  }

  func retainPresentationPlacement(_ placement: PresentationPlacement) {
    presentationPlacement = placement
  }

  func reclaimFromPresentation() {
    presentationEpoch &+= 1
    presentationPhase = .active
    presentationPlacement = nil
    presentationParentID = nil
    isPresentationOnly = false
  }

  func completePresentationTransitionIfCurrent(_ token: PresentationTransitionToken) -> Bool {
    guard token == currentPresentationTransitionToken else { return false }
    presentationPhase = .active
    markDirty(.paint)
    return true
  }

  func detachFromGraph() {
    observationToken?.isActive = false
    graph = nil
    parent = nil
    for child in children {
      child.detachFromGraph()
    }
  }

  func makeSnapshot() -> Snapshot {
    Snapshot(
      identity: identity,
      parent: parent,
      children: children,
      value: value,
      primitive: primitive,
      focusMetadata: focusMetadata,
      hitTestMetadata: hitTestMetadata,
      environmentDependencies: environmentDependencies,
      environment: environment,
      preferenceDependencies: preferenceDependencies,
      cachedSize: cachedSize,
      cachedFrame: cachedFrame,
      paintBounds: paintBounds,
      localDirtyFlags: localDirtyFlags,
      dirtyFlags: dirtyFlags,
      dirtyGeneration: dirtyGeneration,
      layoutGeneration: layoutGeneration,
      isPresentationOnly: isPresentationOnly,
      presentationPhase: presentationPhase,
      presentationEpoch: presentationEpoch,
      presentationPlacement: presentationPlacement,
      lifecycle: lifecycle,
      removalPolicy: removalPolicy,
      presentationParentID: presentationParentID,
      stateSlots: stateSlots,
      dynamicPropertyValues: dynamicPropertyValues,
      metadataSlots: metadataSlots,
      preferenceValues: preferenceValues,
      observationToken: observationToken,
      mountedNodeAttributes: mountedNodeAttributes
    )
  }

  func prepareMetadataForFrame() {
    metadataSlots = metadataSlots.mapValues { value in
      guard let snapshottingValue = value as? any FrameSnapshottingNodeMetadata else { return value }
      return snapshottingValue.makeFrameSnapshotCopy()
    }
  }

  func restore(_ snapshot: Snapshot, graph: ViewGraph) {
    identity = snapshot.identity
    parent = snapshot.parent
    children = snapshot.children
    value = snapshot.value
    primitive = snapshot.primitive
    focusMetadata = snapshot.focusMetadata
    hitTestMetadata = snapshot.hitTestMetadata
    environmentDependencies = snapshot.environmentDependencies
    environment = snapshot.environment
    preferenceDependencies = snapshot.preferenceDependencies
    cachedSize = snapshot.cachedSize
    cachedFrame = snapshot.cachedFrame
    paintBounds = snapshot.paintBounds
    localDirtyFlags = snapshot.localDirtyFlags
    dirtyFlags = snapshot.dirtyFlags
    dirtyGeneration = snapshot.dirtyGeneration
    layoutGeneration = snapshot.layoutGeneration
    isPresentationOnly = snapshot.isPresentationOnly
    presentationPhase = snapshot.presentationPhase
    presentationEpoch = snapshot.presentationEpoch
    presentationPlacement = snapshot.presentationPlacement
    lifecycle = snapshot.lifecycle
    removalPolicy = snapshot.removalPolicy
    presentationParentID = snapshot.presentationParentID
    self.graph = graph
    stateSlots = snapshot.stateSlots
    dynamicPropertyValues = snapshot.dynamicPropertyValues
    metadataSlots = snapshot.metadataSlots
    preferenceValues = snapshot.preferenceValues
    observationToken?.isActive = false
    observationToken = snapshot.observationToken
    mountedNodeAttributes = snapshot.mountedNodeAttributes
    observationToken?.node = self
    observationToken?.isActive = true
  }

  func dynamicPropertyValue<Value>(at index: Int, as type: Value.Type) -> Value? {
    dynamicPropertyValues[index] as? Value
  }

  func setDynamicPropertyValue(_ value: some Any, at index: Int) {
    dynamicPropertyValues[index] = value
    invalidate(.structure)
  }

  private func applyDeclarativeStorage(_ descriptor: NodeDescriptor) {
    if let values = descriptor.evaluatedDynamicPropertyValues {
      dynamicPropertyValues = values
    }
    let previousPreferences = preferenceValues
    preferenceValues = descriptor.resolvedPreferences
    if preferenceDependencies.contains(where: { previousPreferences.differs(from: preferenceValues, for: $0) }) {
      markDirty(.structure)
    }
    observationToken?.isActive = false
    observationToken = descriptor.observationToken
    observationToken?.node = self
    observationToken?.isActive = true
    for location in descriptor.dynamicPropertyLocations {
      location.bind(propertyIndex: location.propertyIndexForBinding, to: self)
    }
  }
}

/// Defines a type-safe metadata slot on a mounted node.
public protocol NodeMetadataKey {
  /// The metadata value type.
  associatedtype Value
}

private struct StateSlotID: Hashable {
  let namespace: ObjectIdentifier
  let valueType: ObjectIdentifier

  init(_ key: StateKey<some Any>) {
    self.namespace = key.namespace
    self.valueType = key.valueType
  }
}
