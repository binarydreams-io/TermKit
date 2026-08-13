import Observation

public enum ViewInvalidationContext {
    @TaskLocal public static var transaction: (any Sendable)?
}

@MainActor
public protocol DynamicProperty {
    mutating func update()
}

public extension DynamicProperty {
    mutating func update() {}
}

@MainActor
public protocol View {
    @ViewBuilder var graphBody: [NodeDescriptor] { get }
}

@MainActor
@resultBuilder
public enum ViewBuilder {
    public static func buildExpression(_ expression: NodeDescriptor) -> [NodeDescriptor] {
        [expression]
    }

    public static func buildExpression<Content: View>(_ expression: Content) -> [NodeDescriptor] {
        [NodeDescriptor.declarative(expression)]
    }

    public static func buildExpression(_ expression: [NodeDescriptor]) -> [NodeDescriptor] {
        expression
    }

    public static func buildExpression(_ expression: Void) -> [NodeDescriptor] {
        []
    }

    public static func buildBlock(_ components: [NodeDescriptor]...) -> [NodeDescriptor] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [NodeDescriptor]?) -> [NodeDescriptor] {
        component ?? []
    }

    public static func buildEither(first component: [NodeDescriptor]) -> [NodeDescriptor] {
        component.map { $0.inBranch(0) }
    }

    public static func buildEither(second component: [NodeDescriptor]) -> [NodeDescriptor] {
        component.map { $0.inBranch(1) }
    }

    public static func buildArray(_ components: [[NodeDescriptor]]) -> [NodeDescriptor] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [NodeDescriptor]) -> [NodeDescriptor] {
        component
    }
}

public typealias ViewGraphBuilder = ViewBuilder

@MainActor
public func buildViewGraph(@ViewBuilder _ content: () -> [NodeDescriptor]) -> [NodeDescriptor] {
    content().enumerated().map { $0.element.atIndex($0.offset) }
}

public struct Binding<Value> {
    private let getValue: @MainActor @Sendable () -> Value
    private let setValue: @MainActor @Sendable (Value) -> Void

    @MainActor
    public init(
        get: @escaping @MainActor @Sendable () -> Value,
        set: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        getValue = get
        setValue = set
    }

    @MainActor
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }
}

extension Binding: Sendable where Value: Sendable {}

@MainActor
@propertyWrapper
public struct State<Value>: DynamicProperty {
    private let location: StateLocation<Value>

    public init(wrappedValue: Value) {
        location = StateLocation(initialValue: wrappedValue)
    }

    public var wrappedValue: Value {
        get { location.value }
        nonmutating set { location.value = newValue }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { location.value }, set: { location.value = $0 })
    }
}

extension State: DynamicPropertyLocation {
    var propertyIndexForBinding: Int { location.propertyIndex ?? 0 }

    func bind(propertyIndex: Int, to node: MountedNode?) {
        location.bind(propertyIndex: propertyIndex, to: node)
    }
}

public struct BodyMutationDiagnostic: Error, Equatable, CustomStringConvertible {
    public let identity: StructuralIdentity
    public let propertyIndex: Int

    public init(identity: StructuralIdentity, propertyIndex: Int) {
        self.identity = identity
        self.propertyIndex = propertyIndex
    }

    public var description: String {
        "State at property index \(propertyIndex) was mutated while evaluating the body of \(identity)."
    }
}

@MainActor
final class StateLocation<Value> {
    let initialValue: Value
    var propertyIndex: Int?
    weak var node: MountedNode?

    init(initialValue: Value) {
        self.initialValue = initialValue
    }

    var value: Value {
        get {
            if let context = BodyEvaluationContext.current, let propertyIndex {
                return context.value(at: propertyIndex, default: initialValue)
            }
            guard let propertyIndex else { return initialValue }
            return node?.dynamicPropertyValue(at: propertyIndex, as: Value.self) ?? initialValue
        }
        set {
            if let context = BodyEvaluationContext.current, let propertyIndex {
                context.recordMutation(at: propertyIndex)
                return
            }
            guard let propertyIndex else { return }
            node?.setDynamicPropertyValue(newValue, at: propertyIndex)
        }
    }

    func bind(propertyIndex: Int, to node: MountedNode?) {
        self.propertyIndex = propertyIndex
        self.node = node
    }
}

@MainActor
protocol DynamicPropertyLocation {
    var propertyIndexForBinding: Int { get }
    func bind(propertyIndex: Int, to node: MountedNode?)
}

@MainActor
final class BodyEvaluationContext {
    static var current: BodyEvaluationContext?

    let identity: StructuralIdentity
    let existingNode: MountedNode?
    let environment: EnvironmentValues
    var values: [Int: Any]
    var environmentDependencies: Set<EnvironmentDependencyKey> = []
    var preferenceDependencies: Set<PreferenceDependencyKey> = []
    var mutation: BodyMutationDiagnostic?
    var locations: [any DynamicPropertyLocation] = []
    let observationToken = ObservationToken()

    init(identity: StructuralIdentity, existingNode: MountedNode?, environment: EnvironmentValues) {
        self.identity = identity
        self.existingNode = existingNode
        self.environment = environment
        values = existingNode?.dynamicPropertyValues ?? [:]
    }

    func value<Value>(at index: Int, default defaultValue: Value) -> Value {
        if let value = values[index] as? Value {
            return value
        }
        values[index] = defaultValue
        return defaultValue
    }

    func recordMutation(at index: Int) {
        mutation = BodyMutationDiagnostic(identity: identity, propertyIndex: index)
    }
}

@MainActor
func bindDynamicProperties(in value: Any, to context: BodyEvaluationContext) {
    var index = 0
    for child in Mirror(reflecting: value).children {
        if var property = child.value as? any DynamicProperty {
            property.update()
        }
        if let location = child.value as? any DynamicPropertyLocation {
            location.bind(propertyIndex: index, to: context.existingNode)
            context.locations.append(location)
            index += 1
        }
    }
}

@MainActor
func evaluateBody<Content: View>(_ view: Content, context: BodyEvaluationContext) -> [NodeDescriptor] {
    bindDynamicProperties(in: view, to: context)
    let previous = BodyEvaluationContext.current
    BodyEvaluationContext.current = context
    defer { BodyEvaluationContext.current = previous }
    return withObservationTracking {
        view.graphBody
    } onChange: { [weak token = context.observationToken] in
        Task { @MainActor in token?.invalidate() }
    }
}

@MainActor
final class ObservationToken {
    weak var node: MountedNode?
    var isActive = false

    func invalidate() {
        guard isActive else { return }
        node?.invalidate(.structure)
    }
}
