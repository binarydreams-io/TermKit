/// Uniquely identifies a mounted node within a view graph.
public struct NodeID: RawRepresentable, Hashable, Comparable, Sendable {
    /// The numeric identifier value.
    public let rawValue: UInt64

    /// Creates a node identifier from a raw value.
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// Returns whether the left identifier precedes the right identifier.
    public static func < (lhs: NodeID, rhs: NodeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Type-erases a hashable key used in structural identity.
public struct StructuralKey: Hashable, Sendable, CustomStringConvertible {
    private let value: any Hashable & Sendable

    /// Creates a type-erased structural key.
    public init<Key: Hashable & Sendable>(_ value: Key) {
        self.value = value
    }

    /// Returns whether two structural keys contain equal values.
    public static func == (lhs: StructuralKey, rhs: StructuralKey) -> Bool {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    /// Hashes the stored key into a hasher.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(value))
    }

    /// A textual representation of the stored key.
    public var description: String {
        String(describing: value)
    }
}

/// Identifies a node by type, position or key, and conditional branches.
public struct StructuralIdentity: Hashable, Sendable, CustomStringConvertible {
    /// The type represented by the node.
    public let type: Any.Type
    /// The node's position among its siblings.
    public let index: Int
    /// The explicit identity key, if present.
    public let key: StructuralKey?
    /// The nested conditional branch path.
    public let branchPath: [Int]

    /// The last component of the branch path, if present.
    public var branch: Int? {
        branchPath.last
    }

    /// Creates an index-based structural identity.
    public init(type: Any.Type, index: Int = 0, branch: Int? = nil) {
        self.init(type: type, index: index, keyStorage: nil, branchPath: branch.map { [$0] } ?? [])
    }

    /// Creates a key-based structural identity.
    public init<Key: Hashable & Sendable>(type: Any.Type, key: Key, index: Int = 0, branch: Int? = nil) {
        self.init(type: type, index: index, keyStorage: StructuralKey(key), branchPath: branch.map { [$0] } ?? [])
    }

    private init(type: Any.Type, index: Int, keyStorage: StructuralKey?, branchPath: [Int]) {
        precondition(index >= 0, "A structural index must not be negative.")
        self.type = type
        self.index = index
        key = keyStorage
        self.branchPath = branchPath
    }

    /// Returns whether two structural identities identify the same position.
    public static func == (lhs: StructuralIdentity, rhs: StructuralIdentity) -> Bool {
        guard ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type), lhs.branchPath == rhs.branchPath else {
            return false
        }

        switch (lhs.key, rhs.key) {
        case let (.some(lhsKey), .some(rhsKey)):
            return lhsKey == rhsKey
        case (.none, .none):
            return lhs.index == rhs.index
        default:
            return false
        }
    }

    /// Hashes the structural identity into a hasher.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type))
        hasher.combine(branchPath)
        if let key {
            hasher.combine(true)
            hasher.combine(key)
        } else {
            hasher.combine(false)
            hasher.combine(index)
        }
    }

    /// A diagnostic representation of the structural identity.
    ///
    /// - Complexity: O(*b*), where *b* is the branch path length.
    public var description: String {
        let position = key.map { "key=\($0)" } ?? "index=\(index)"
        let branchDescription = branchPath.isEmpty ? "" : ", branch=\(branchPath.map(String.init).joined(separator: "."))"
        return "\(String(reflecting: type))(\(position)\(branchDescription))"
    }

    func atIndex(_ index: Int) -> StructuralIdentity {
        StructuralIdentity(type: type, index: index, keyStorage: key, branchPath: branchPath)
    }

    func inBranch(_ branch: Int) -> StructuralIdentity {
        StructuralIdentity(type: type, index: index, keyStorage: key, branchPath: branchPath + [branch])
    }
}

/// Identifies a typed state slot on a mounted node.
public struct StateKey<Value>: Hashable, Sendable {
    let namespace: ObjectIdentifier
    let valueType: ObjectIdentifier

    /// Creates a state key in a type-based namespace.
    public init(_ namespace: Any.Type, as valueType: Value.Type = Value.self) {
        self.namespace = ObjectIdentifier(namespace)
        self.valueType = ObjectIdentifier(valueType)
    }
}

/// Identifies an environment value dependency by key type.
public struct EnvironmentDependencyKey: Hashable, Sendable {
    private let identifier: ObjectIdentifier

    /// Creates a dependency key for a type.
    public init(_ type: Any.Type) {
        identifier = ObjectIdentifier(type)
    }

    init(identifier: ObjectIdentifier) {
        self.identifier = identifier
    }
}

/// Identifies a preference value dependency by key type.
public struct PreferenceDependencyKey: Hashable, Sendable {
    private let identifier: ObjectIdentifier

    /// Creates a dependency key for a type.
    public init(_ type: Any.Type) {
        identifier = ObjectIdentifier(type)
    }
}

/// Describes duplicate child identities in a view graph.
public struct DuplicateIdentityDiagnostic: Error, Equatable, CustomStringConvertible {
    /// The parent identity, or `nil` for the graph root.
    public let parent: StructuralIdentity?
    /// The duplicated child identity.
    public let identity: StructuralIdentity
    /// The index of the first occurrence.
    public let firstIndex: Int
    /// The index of the duplicate occurrence.
    public let duplicateIndex: Int

    /// Creates a duplicate identity diagnostic.
    public init(
        parent: StructuralIdentity?,
        identity: StructuralIdentity,
        firstIndex: Int,
        duplicateIndex: Int
    ) {
        self.parent = parent
        self.identity = identity
        self.firstIndex = firstIndex
        self.duplicateIndex = duplicateIndex
    }

    /// A diagnostic message that describes the duplicate identity.
    public var description: String {
        let parentDescription = parent.map(String.init(describing:)) ?? "graph root"
        return "Duplicate structural identity \(identity) at child indexes \(firstIndex) and \(duplicateIndex) under \(parentDescription)."
    }
}
