public protocol EnvironmentKey {
    associatedtype Value: Equatable & Sendable
    static var defaultValue: Value { get }
}

public struct EnvironmentValues: @unchecked Sendable {
    private var storage: [EnvironmentDependencyKey: AnyEnvironmentValue] = [:]

    public init() {}

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
            return lhs.equals(rhs) == false
        case (.none, .none):
            return false
        default:
            return true
        }
    }

    package func value(forKeyIdentifier identifier: ObjectIdentifier) -> (any Sendable)? {
        storage[EnvironmentDependencyKey(identifier: identifier)]?.value
    }
}

private struct AnyEnvironmentValue: @unchecked Sendable {
    let value: any Sendable
    private let isEqual: (any Sendable) -> Bool

    init<Value: Equatable & Sendable>(_ value: Value) {
        self.value = value
        isEqual = { ($0 as? Value) == value }
    }

    func equals(_ other: Self) -> Bool {
        isEqual(other.value)
    }
}

@MainActor
@propertyWrapper
public struct Environment<Key: EnvironmentKey>: DynamicProperty {
    public init(_ key: Key.Type) {}

    public var wrappedValue: Key.Value {
        BodyEvaluationContext.current?.environment[Key.self] ?? Key.defaultValue
    }
}

private struct EnvironmentWritingView<Content: View, Key: EnvironmentKey>: View {
    let content: Content
    let value: Key.Value

    var graphBody: [NodeDescriptor] {
        [NodeDescriptor.declarative(content).settingEnvironment(Key.self, to: value)]
    }
}

public extension View {
    func environment<Key: EnvironmentKey>(_ key: Key.Type, _ value: Key.Value) -> some View {
        EnvironmentWritingView<Self, Key>(content: self, value: value)
    }
}
