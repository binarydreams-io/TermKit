public protocol PreferenceKey {
    associatedtype Value: Equatable & Sendable
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

public extension PreferenceKey {
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue()
    }
}

public struct PreferenceValues: @unchecked Sendable {
    private var storage: [PreferenceDependencyKey: AnyPreferenceValue] = [:]

    public init() {}

    @MainActor
    public subscript<Key: PreferenceKey>(key: Key.Type) -> Key.Value {
        get {
            BodyEvaluationContext.current?.preferenceDependencies.insert(PreferenceDependencyKey(key))
            return storage[PreferenceDependencyKey(key)]?.value as? Key.Value ?? Key.defaultValue
        }
        set {
            storage[PreferenceDependencyKey(key)] = AnyPreferenceValue(Key.self, value: newValue)
        }
    }

    @MainActor
    mutating func reduce(_ other: Self) {
        for (key, next) in other.storage {
            if let current = storage[key] {
                storage[key] = current.reducing(next)
            } else {
                storage[key] = next
            }
        }
    }

    func value<Key: PreferenceKey>(for key: Key.Type) -> Key.Value {
        storage[PreferenceDependencyKey(key)]?.value as? Key.Value ?? Key.defaultValue
    }

    func differs(from other: Self, for key: PreferenceDependencyKey) -> Bool {
        switch (storage[key], other.storage[key]) {
        case let (.some(lhs), .some(rhs)):
            return lhs.equals(rhs) == false
        case (.none, .none):
            return false
        default:
            return true
        }
    }
}

private struct AnyPreferenceValue: @unchecked Sendable {
    let value: Any
    private let reduceValue: (Any, Any) -> Any
    private let areEqual: (Any, Any) -> Bool

    init<Key: PreferenceKey>(_ key: Key.Type, value: Key.Value) {
        self.value = value
        reduceValue = { current, next in
            var result = current as? Key.Value ?? Key.defaultValue
            Key.reduce(value: &result) { next as? Key.Value ?? Key.defaultValue }
            return result
        }
        areEqual = { ($0 as? Key.Value) == ($1 as? Key.Value) }
    }

    func reducing(_ next: Self) -> Self {
        let reduced = reduceValue(value, next.value)
        return Self(value: reduced, reduceValue: reduceValue, areEqual: areEqual)
    }

    private init(value: Any, reduceValue: @escaping (Any, Any) -> Any, areEqual: @escaping (Any, Any) -> Bool) {
        self.value = value
        self.reduceValue = reduceValue
        self.areEqual = areEqual
    }

    func equals(_ other: Self) -> Bool {
        areEqual(value, other.value)
    }
}

@MainActor
@propertyWrapper
public struct Preference<Key: PreferenceKey>: DynamicProperty {
    public init(_ key: Key.Type) {}

    public var wrappedValue: Key.Value {
        BodyEvaluationContext.current?.preferenceDependencies.insert(PreferenceDependencyKey(Key.self))
        return BodyEvaluationContext.current?.existingNode?.preferenceValues.value(for: Key.self) ?? Key.defaultValue
    }
}

private struct PreferenceWritingView<Content: View, Key: PreferenceKey>: View {
    let content: Content
    let value: Key.Value

    var graphBody: [NodeDescriptor] {
        [NodeDescriptor.declarative(content).settingPreference(Key.self, to: value)]
    }
}

public extension View {
    func preference<Key: PreferenceKey>(key: Key.Type, value: Key.Value) -> some View {
        PreferenceWritingView<Self, Key>(content: self, value: value)
    }
}
