import TUIFoundation

public struct FocusMetadata: Equatable, Sendable {
    public var isFocusable: Bool
    public var order: Int?

    public init(isFocusable: Bool = false, order: Int? = nil) {
        self.isFocusable = isFocusable
        self.order = order
    }
}

public struct HitTestMetadata: Equatable, Sendable {
    public var isEnabled: Bool
    public var zIndex: Int
    public var disablesDescendants: Bool
    public var modalScope: String?

    public init(isEnabled: Bool = false, zIndex: Int = 0) {
        self.init(
            isEnabled: isEnabled,
            zIndex: zIndex,
            disablesDescendants: false,
            modalScope: nil
        )
    }

    public init(
        isEnabled: Bool = false,
        zIndex: Int = 0,
        disablesDescendants: Bool,
        modalScope: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.zIndex = zIndex
        self.disablesDescendants = disablesDescendants
        self.modalScope = modalScope
    }
}

public struct NodeLifecycle {
    public typealias Handler = @MainActor (MountedNode) -> Void

    public var onMount: Handler?
    public var onUpdate: Handler?
    public var onRemove: Handler?

    public init(onMount: Handler? = nil, onUpdate: Handler? = nil, onRemove: Handler? = nil) {
        self.onMount = onMount
        self.onUpdate = onUpdate
        self.onRemove = onRemove
    }
}

public enum NodeRemovalPolicy: Hashable, Sendable {
    case immediate
    case retainForTransition
}

@MainActor
public protocol MountedNodeAttribute {
    var id: AnyHashable { get }
    var stagedDirtyFlags: DirtyFlags { get }
    func apply(
        to node: MountedNode,
        replacing previous: (any MountedNodeAttribute)?
    ) -> [MountedNodeAttributeAction]
    func remove(from node: MountedNode) -> [MountedNodeAttributeAction]
    func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample
}

/// A request for the next frame from a mounted view attribute.
package struct MountedFrameDemand: Sendable, Hashable {
    /// The preferred interval between frames.
    package var cadence: TUIDuration?

    /// The absolute instant for the next frame.
    package var deadline: TimeInstant?

    /// Creates a mounted frame request.
    package init(cadence: TUIDuration? = nil, deadline: TimeInstant? = nil) {
        if let cadence {
            precondition(cadence > .zero, "A frame cadence must be positive.")
        }
        self.cadence = cadence
        self.deadline = deadline
    }

    /// Combines two requests and keeps their earliest frame requirements.
    package func merging(_ other: Self) -> Self {
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
package protocol MountedFrameDemandAttribute: MountedNodeAttribute {
    func frameDemand(after instant: TimeInstant) -> MountedFrameDemand?
}

/// A mounted attribute whose presentation requires declarative body evaluation.
@MainActor
package protocol MountedStructureSamplingAttribute: MountedNodeAttribute {
    func requiresStructureSampling(on node: MountedNode, at instant: TimeInstant) -> Bool
}

public typealias MountedNodeAttributeAction = @MainActor @Sendable () -> Void

@MainActor
public struct MountedNodeAttributeSample {
    public var isActive: Bool
    public var dirtyFlags: DirtyFlags
    public var completionActions: [MountedNodeAttributeAction]

    public init(
        isActive: Bool = false,
        dirtyFlags: DirtyFlags = [],
        completionActions: [MountedNodeAttributeAction] = []
    ) {
        self.isActive = isActive
        self.dirtyFlags = dirtyFlags
        self.completionActions = completionActions
    }

    public static let inactive = MountedNodeAttributeSample()
}

public extension MountedNodeAttribute {
    var stagedDirtyFlags: DirtyFlags { [] }
    func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample { .inactive }
}

@MainActor
public protocol FrameSnapshottingNodeMetadata: AnyObject {
    func makeFrameSnapshotCopy() -> any FrameSnapshottingNodeMetadata
}

public struct NodeDescriptor {
    public var identity: StructuralIdentity
    public var value: (any Sendable)?
    public var primitive: (any Sendable)?
    public var children: [NodeDescriptor]
    public var focus: FocusMetadata
    public var hitTest: HitTestMetadata
    public var environmentDependencies: Set<EnvironmentDependencyKey>
    public var preferenceDependencies: Set<PreferenceDependencyKey>
    public var dirtyOnUpdate: DirtyFlags
    public var removalPolicy: NodeRemovalPolicy
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
    var expansionScope: (@MainActor (MountedNode?, @MainActor () throws -> NodeDescriptor) throws -> NodeDescriptor)?

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
        bodyEvaluator = nil
        environmentTransform = nil
        effectiveEnvironment = nil
        emittedPreferences = PreferenceValues()
        resolvedPreferences = PreferenceValues()
        evaluatedDynamicPropertyValues = nil
        dynamicPropertyLocations = []
        observationToken = nil
        mountedNodeAttributes = [:]
        expansionScope = nil
    }

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

    public init<Key: Hashable & Sendable>(
        type: Any.Type,
        index: Int = 0,
        key: Key,
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
            identity: StructuralIdentity(type: type, index: index, key: key, branch: branch),
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

    public func value<Value>(as type: Value.Type = Value.self) -> Value? {
        value as? Value
    }

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

    @MainActor
    public static func declarative<Content: View>(_ view: Content) -> NodeDescriptor {
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

    @MainActor
    public func attribute(_ attribute: any MountedNodeAttribute) -> NodeDescriptor {
        var copy = self
        copy.mountedNodeAttributes[attribute.id] = attribute
        return copy
    }

    @MainActor
    public func scopedExpansion(
        _ scope: @escaping @MainActor (MountedNode?, @MainActor () throws -> NodeDescriptor) throws -> NodeDescriptor
    ) -> NodeDescriptor {
        var copy = self
        copy.expansionScope = scope
        return copy
    }
}

public struct DescriptorView: View {
    public let descriptor: NodeDescriptor

    public init(_ descriptor: NodeDescriptor) {
        self.descriptor = descriptor
    }

    public var graphBody: [NodeDescriptor] {
        [descriptor]
    }
}
