/// Defines a typed value in the view environment.
public protocol EnvironmentKey {
  /// The stored value type.
  associatedtype Value: Equatable & Sendable
  /// The value used when the environment contains no override.
  static var defaultValue: Value { get }
}

/// Stores typed environment values.
public struct EnvironmentValues: Sendable {
  private var storage: [EnvironmentDependencyKey: AnyEnvironmentValue] = [:]

  /// Creates an environment with default values.
  public init() {}

  /// Accesses the value associated with an environment key.
  @MainActor
  public subscript<Key: EnvironmentKey>(key: Key.Type) -> Key.Value {
    get {
      BodyEvaluationContext.current?.environmentDependencies.insert(EnvironmentDependencyKey(key))
      return storage[EnvironmentDependencyKey(key)]?.value as? Key.Value ?? Key.defaultValue
    }
    set {
      storage[EnvironmentDependencyKey(key)] = AnyEnvironmentValue(newValue)
    }
  }

  func differs(from other: Self, for key: EnvironmentDependencyKey) -> Bool {
    switch (storage[key], other.storage[key]) {
    case let (.some(lhs), .some(rhs)):
      lhs.equals(rhs) == false
    case (.none, .none):
      false
    default:
      true
    }
  }

  func value(forKeyIdentifier identifier: ObjectIdentifier) -> (any Sendable)? {
    storage[EnvironmentDependencyKey(identifier: identifier)]?.value
  }
}

/// Provides the current terminal size in cells.
public enum TerminalSizeEnvironmentKey: EnvironmentKey {
  /// The size used outside a terminal runtime.
  public static let defaultValue = CellSize.zero
}

private struct AnyEnvironmentValue: Sendable {
  let value: any Sendable
  private let isEqual: @Sendable (any Sendable) -> Bool

  init<Value: Equatable & Sendable>(_ value: Value) {
    self.value = value
    self.isEqual = { ($0 as? Value) == value }
  }

  func equals(_ other: Self) -> Bool {
    isEqual(other.value)
  }
}

/// Reads a typed value from the environment during body evaluation.
@MainActor
@propertyWrapper
public struct Environment<Key: EnvironmentKey>: DynamicProperty {
  /// Creates an environment property for a key.
  public init(_ key: Key.Type) {}

  /// The current value for the environment key.
  public var wrappedValue: Key.Value {
    BodyEvaluationContext.current?.environment[Key.self] ?? Key.defaultValue
  }
}

private struct EnvironmentWritingView<Content: View, Key: EnvironmentKey>: View {
  let content: Content
  let value: Key.Value

  var graphBody: [NodeDescriptor] {
    [NodeDescriptor.makeDeclarative(content).settingEnvironment(Key.self, to: value)]
  }
}

extension View {
  /// Sets an environment value for this view and its descendants.
  public func environment<Key: EnvironmentKey>(_ key: Key.Type, value: Key.Value) -> some View {
    EnvironmentWritingView<Self, Key>(content: self, value: value)
  }
}
