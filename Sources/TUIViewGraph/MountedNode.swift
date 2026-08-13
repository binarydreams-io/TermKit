import TUIFoundation

public enum NodePresentationPhase: Sendable, Hashable {
    case inserting
    case active
    case removing
}

public struct PresentationTransitionToken: Sendable, Hashable {
    public let nodeID: NodeID
    public let epoch: UInt64

    public init(nodeID: NodeID, epoch: UInt64) {
        self.nodeID = nodeID
        self.epoch = epoch
    }
}

public struct PresentationPlacement: Sendable, Hashable {
    public let parentID: NodeID?
    public let siblingIndex: Int
    public let previousSiblingID: NodeID?
    public let nextSiblingID: NodeID?

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

public struct DirtyFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        if rawValue & 0b100 != 0 {
            self.rawValue = 0b111
        } else if rawValue & 0b010 != 0 {
            self.rawValue = 0b011
        } else {
            self.rawValue = rawValue & 0b001
        }
    }

    public static let paint = DirtyFlags(rawValue: 0b001)
    public static let layout = DirtyFlags(rawValue: 0b010)
    public static let structure = DirtyFlags(rawValue: 0b100)
}

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

    public let id: NodeID
    public internal(set) var identity: StructuralIdentity
    public internal(set) weak var parent: MountedNode?
    public internal(set) var children: [MountedNode]
    public internal(set) var value: (any Sendable)?
    public internal(set) var primitive: (any Sendable)?
    public internal(set) var focusMetadata: FocusMetadata
    public internal(set) var hitTestMetadata: HitTestMetadata
    public internal(set) var environmentDependencies: Set<EnvironmentDependencyKey>
    package internal(set) var environment: EnvironmentValues
    public internal(set) var preferenceDependencies: Set<PreferenceDependencyKey>
    public internal(set) var cachedSize: CellSize?
    public internal(set) var cachedFrame: CellRect?
    public internal(set) var paintBounds: CellRect
    public internal(set) var localDirtyFlags: DirtyFlags
    public internal(set) var dirtyFlags: DirtyFlags
    public internal(set) var dirtyGeneration: UInt64
    public internal(set) var layoutGeneration: UInt64
    public internal(set) var isPresentationOnly: Bool
    public internal(set) var presentationPhase: NodePresentationPhase
    public internal(set) var presentationPlacement: PresentationPlacement?

    var lifecycle: NodeLifecycle
    var removalPolicy: NodeRemovalPolicy
    var presentationParentID: NodeID?
    private var presentationEpoch: UInt64
    weak var graph: ViewGraph?
    private var stateSlots: [StateSlotID: Any]
    var dynamicPropertyValues: [Int: Any]
    private var metadataSlots: [ObjectIdentifier: Any]
    public internal(set) var preferenceValues: PreferenceValues
    private var observationToken: ObservationToken?
    var mountedNodeAttributes: [AnyHashable: any MountedNodeAttribute]

    init(id: NodeID, descriptor: NodeDescriptor, graph: ViewGraph) {
        self.id = id
        identity = descriptor.identity
        children = []
        value = descriptor.value
        primitive = descriptor.primitive
        focusMetadata = descriptor.focus
        hitTestMetadata = descriptor.hitTest
        environmentDependencies = descriptor.environmentDependencies
        environment = descriptor.effectiveEnvironment ?? EnvironmentValues()
        preferenceDependencies = descriptor.preferenceDependencies
        cachedSize = nil
        cachedFrame = nil
        paintBounds = .zero
        localDirtyFlags = .structure
        dirtyFlags = .structure
        dirtyGeneration = 1
        layoutGeneration = 0
        isPresentationOnly = false
        presentationPhase = .active
        presentationPlacement = nil
        lifecycle = descriptor.lifecycle
        removalPolicy = descriptor.removalPolicy
        presentationParentID = nil
        presentationEpoch = 0
        self.graph = graph
        stateSlots = [:]
        dynamicPropertyValues = [:]
        metadataSlots = [:]
        preferenceValues = PreferenceValues()
        observationToken = nil
        mountedNodeAttributes = descriptor.mountedNodeAttributes
        applyDeclarativeStorage(descriptor)
    }

    public var isFocusable: Bool {
        isPresentationOnly == false
            && focusMetadata.isFocusable
            && ancestorsDisableHitTesting == false
    }

    public var acceptsHitTesting: Bool {
        isPresentationOnly == false
            && hitTestMetadata.isEnabled
            && ancestorsDisableHitTesting == false
    }

    public var isInteractive: Bool {
        isFocusable || acceptsHitTesting
    }

    public var activeModalScope: String? {
        sequence(first: self, next: \.parent).compactMap(\.hitTestMetadata.modalScope).first
    }

    private var ancestorsDisableHitTesting: Bool {
        guard let parent else { return false }
        return sequence(first: parent, next: \.parent).contains { $0.hitTestMetadata.disablesDescendants }
    }

    public func value<Value>(as type: Value.Type = Value.self) -> Value? {
        value as? Value
    }

    public func primitive<Primitive>(as type: Primitive.Type = Primitive.self) -> Primitive? {
        primitive as? Primitive
    }

    public func state<Value>(for key: StateKey<Value>) -> Value? {
        stateSlots[StateSlotID(key)] as? Value
    }

    @discardableResult
    public func state<Value>(for key: StateKey<Value>, default makeValue: @autoclosure () -> Value) -> Value {
        if let value = state(for: key) {
            return value
        }
        let value = makeValue()
        stateSlots[StateSlotID(key)] = value
        return value
    }

    public func setState<Value>(_ value: Value, for key: StateKey<Value>) {
        stateSlots[StateSlotID(key)] = value
        invalidate(.structure)
    }

    public func removeState<Value>(for key: StateKey<Value>) {
        guard stateSlots.removeValue(forKey: StateSlotID(key)) != nil else { return }
        invalidate(.structure)
    }

    public func metadata<Key: NodeMetadataKey>(for key: Key.Type) -> Key.Value? {
        metadataSlots[ObjectIdentifier(key)] as? Key.Value
    }

    public func setMetadata<Key: NodeMetadataKey>(_ value: Key.Value?, for key: Key.Type) {
        metadataSlots[ObjectIdentifier(key)] = value
    }

    public func preference<Key: PreferenceKey>(_ key: Key.Type) -> Key.Value {
        preferenceValues.value(for: key)
    }

    public func cache(size: CellSize, frame: CellRect, paintBounds: CellRect? = nil) {
        cachedSize = size
        cachedFrame = frame
        self.paintBounds = paintBounds ?? frame
    }

    public func invalidate(_ flags: DirtyFlags) {
        graph?.invalidate(self, flags)
    }

    public func clearDirtyFlags() {
        localDirtyFlags = []
        dirtyFlags = []
    }

    @discardableResult
    public func completePresentationTransition() -> Bool {
        completePresentationTransition(currentPresentationTransitionToken)
    }

    @discardableResult
    public func completePresentationTransition(_ token: PresentationTransitionToken) -> Bool {
        graph?.completeTransition(for: id, token: token) ?? false
    }

    public var currentPresentationTransitionToken: PresentationTransitionToken {
        PresentationTransitionToken(nodeID: id, epoch: presentationEpoch)
    }

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

    func setDynamicPropertyValue<Value>(_ value: Value, at index: Int) {
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

public protocol NodeMetadataKey {
    associatedtype Value
}

private struct StateSlotID: Hashable {
    let namespace: ObjectIdentifier
    let valueType: ObjectIdentifier

    init<Value>(_ key: StateKey<Value>) {
        namespace = key.namespace
        valueType = key.valueType
    }
}
