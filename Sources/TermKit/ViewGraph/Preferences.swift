/// Defines a typed value that descendants propagate to ancestors.
public protocol PreferenceKey: Sendable {
    /// The preference value type.
    associatedtype Value: Equatable & Sendable
    /// The value used when descendants emit no preference.
    static var defaultValue: Value { get }
    /// Combines an accumulated value with the next descendant value.
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey {
    /// Replaces the accumulated value with the next descendant value.
    public static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue()
    }
}

/// Stores typed preference values.
public struct PreferenceValues: Sendable {
    private var storage: [PreferenceDependencyKey: AnyPreferenceValue] = [:]

    /// Creates an empty preference collection.
    public init() {}

    /// Accesses the value associated with a preference key.
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

private struct AnyPreferenceValue: Sendable {
    let value: any Sendable
    private let reduceValue: @Sendable (any Sendable, any Sendable) -> any Sendable
    private let areEqual: @Sendable (any Sendable, any Sendable) -> Bool

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

    private init(
        value: any Sendable,
        reduceValue: @escaping @Sendable (any Sendable, any Sendable) -> any Sendable,
        areEqual: @escaping @Sendable (any Sendable, any Sendable) -> Bool
    ) {
        self.value = value
        self.reduceValue = reduceValue
        self.areEqual = areEqual
    }

    func equals(_ other: Self) -> Bool {
        areEqual(value, other.value)
    }
}

/// Reads a resolved preference during body evaluation.
@MainActor
@propertyWrapper
public struct Preference<Key: PreferenceKey>: DynamicProperty {
    /// Creates a preference property for a key.
    public init(_ key: Key.Type) {}

    /// The resolved preference value from the mounted node.
    public var wrappedValue: Key.Value {
        BodyEvaluationContext.current?.preferenceDependencies.insert(PreferenceDependencyKey(Key.self))
        return BodyEvaluationContext.current?.existingNode?.preferenceValues.value(for: Key.self) ?? Key.defaultValue
    }
}

private struct PreferenceWritingView<Content: View, Key: PreferenceKey>: View {
    let content: Content
    let value: Key.Value

    var graphBody: [NodeDescriptor] {
        [NodeDescriptor.makeDeclarative(content).settingPreference(Key.self, to: value)]
    }
}

extension View {
    /// Emits a preference value from this view.
    public func preference<Key: PreferenceKey>(key: Key.Type, value: Key.Value) -> some View {
        PreferenceWritingView<Self, Key>(content: self, value: value)
    }
}
