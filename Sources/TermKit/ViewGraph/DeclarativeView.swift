import Observation

/// Provides context attached to the current view invalidation.
public enum ViewInvalidationContext {
  /// The transaction associated with the current invalidation.
  ///
  /// Access the projected task-local value to override the transaction for a scoped operation.
  @TaskLocal public static var transaction: (any Sendable)?
}

/// Defines stored data that updates before view body evaluation.
@MainActor
public protocol DynamicProperty {
  /// Updates the property before body evaluation.
  mutating func update()
}

extension DynamicProperty {
  /// Performs no update for properties without custom update work.
  public mutating func update() {}
}

/// Defines declarative content for the view graph.
@MainActor
public protocol View {
  /// The descriptors that form this view's graph body.
  @ViewBuilder var graphBody: [NodeDescriptor] { get }
}

/// Builds arrays of node descriptors from declarative view content.
@MainActor
@resultBuilder
public enum ViewBuilder {
  /// Builds a component from one node descriptor.
  public static func buildExpression(_ expression: NodeDescriptor) -> [NodeDescriptor] {
    [expression]
  }

  /// Builds a component from a declarative view.
  public static func buildExpression(_ expression: some View) -> [NodeDescriptor] {
    [NodeDescriptor.makeDeclarative(expression)]
  }

  /// Builds a component from an array of descriptors.
  public static func buildExpression(_ expression: [NodeDescriptor]) -> [NodeDescriptor] {
    expression
  }

  /// Builds an empty component from a void expression.
  public static func buildExpression(_ expression: Void) -> [NodeDescriptor] {
    []
  }

  /// Combines block components in source order.
  public static func buildBlock(_ components: [NodeDescriptor]...) -> [NodeDescriptor] {
    components.flatMap(\.self)
  }

  /// Builds an optional component or an empty component.
  public static func buildOptional(_ component: [NodeDescriptor]?) -> [NodeDescriptor] {
    component ?? []
  }

  /// Marks descriptors from the first conditional branch.
  public static func buildEither(first component: [NodeDescriptor]) -> [NodeDescriptor] {
    component.map { $0.inBranch(0) }
  }

  /// Marks descriptors from the second conditional branch.
  public static func buildEither(second component: [NodeDescriptor]) -> [NodeDescriptor] {
    component.map { $0.inBranch(1) }
  }

  /// Combines components produced by a loop.
  public static func buildArray(_ components: [[NodeDescriptor]]) -> [NodeDescriptor] {
    components.flatMap(\.self)
  }

  /// Preserves content guarded by an availability condition.
  public static func buildLimitedAvailability(_ component: [NodeDescriptor]) -> [NodeDescriptor] {
    component
  }
}

/// The result builder used to construct view graphs.
public typealias ViewGraphBuilder = ViewBuilder

/// Builds root descriptors and assigns their structural indexes.
@MainActor
public func buildViewGraph(@ViewBuilder _ content: () -> [NodeDescriptor]) -> [NodeDescriptor] {
  content().enumerated().map { $0.element.atIndex($0.offset) }
}

/// Provides read and write access to a value.
public struct Binding<Value> {
  private let getValue: @MainActor @Sendable () -> Value
  private let setValue: @MainActor @Sendable (_ newValue: Value) -> Void

  /// Creates a binding from read and write operations.
  @MainActor
  public init(
    get: @escaping @MainActor @Sendable () -> Value,
    set: @escaping @MainActor @Sendable (_ newValue: Value) -> Void
  ) {
    self.getValue = get
    self.setValue = set
  }

  /// The value read or written through the binding.
  @MainActor
  public var wrappedValue: Value {
    get { getValue() }
    nonmutating set { setValue(newValue) }
  }
}

extension Binding: Sendable where Value: Sendable {}

/// Stores persistent value state for a declarative view.
@MainActor
@propertyWrapper
public struct State<Value>: DynamicProperty {
  private let location: StateLocation<Value>

  /// Creates state with an initial value.
  public init(wrappedValue: Value) {
    self.location = StateLocation(initialValue: wrappedValue)
  }

  /// The current state value.
  public var wrappedValue: Value {
    get { location.value }
    nonmutating set { location.value = newValue }
  }

  /// A binding to the current state value.
  public var projectedValue: Binding<Value> {
    Binding(get: { location.value }, set: { location.value = $0 })
  }
}

extension State: DynamicPropertyLocation {
  var propertyIndexForBinding: Int {
    location.propertyIndex ?? 0
  }

  func bind(propertyIndex: Int, to node: MountedNode?) {
    location.bind(propertyIndex: propertyIndex, to: node)
  }
}

/// Reports a state mutation during view body evaluation.
public struct BodyMutationDiagnostic: Error, Equatable, CustomStringConvertible {
  /// The identity of the view whose state changed.
  public let identity: StructuralIdentity
  /// The index of the mutated dynamic property.
  public let propertyIndex: Int

  /// Creates a body mutation diagnostic.
  public init(identity: StructuralIdentity, propertyIndex: Int) {
    self.identity = identity
    self.propertyIndex = propertyIndex
  }

  /// A diagnostic message that describes the invalid mutation.
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
    self.values = existingNode?.dynamicPropertyValues ?? [:]
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
func evaluateBody(_ view: some View, context: BodyEvaluationContext) -> [NodeDescriptor] {
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
