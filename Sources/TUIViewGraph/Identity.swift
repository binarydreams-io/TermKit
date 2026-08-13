public struct NodeID: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: NodeID, rhs: NodeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct StructuralKey: Hashable, Sendable, CustomStringConvertible {
    private let value: any Hashable & Sendable

    public init<Key: Hashable & Sendable>(_ value: Key) {
        self.value = value
    }

    public static func == (lhs: StructuralKey, rhs: StructuralKey) -> Bool {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(value))
    }

    public var description: String {
        String(describing: value)
    }
}

public struct StructuralIdentity: Hashable, Sendable, CustomStringConvertible {
    public let type: Any.Type
    public let index: Int
    public let key: StructuralKey?
    public let branchPath: [Int]

    public var branch: Int? {
        branchPath.last
    }

    public init(type: Any.Type, index: Int = 0, branch: Int? = nil) {
        self.init(type: type, index: index, keyStorage: nil, branchPath: branch.map { [$0] } ?? [])
    }

    public init<Key: Hashable & Sendable>(type: Any.Type, index: Int = 0, key: Key, branch: Int? = nil) {
        self.init(type: type, index: index, keyStorage: StructuralKey(key), branchPath: branch.map { [$0] } ?? [])
    }

    private init(type: Any.Type, index: Int, keyStorage: StructuralKey?, branchPath: [Int]) {
        precondition(index >= 0, "A structural index must not be negative.")
        self.type = type
        self.index = index
        key = keyStorage
        self.branchPath = branchPath
    }

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

public struct StateKey<Value>: Hashable, Sendable {
    let namespace: ObjectIdentifier
    let valueType: ObjectIdentifier

    public init(_ namespace: Any.Type, as valueType: Value.Type = Value.self) {
        self.namespace = ObjectIdentifier(namespace)
        self.valueType = ObjectIdentifier(valueType)
    }
}

public struct EnvironmentDependencyKey: Hashable, Sendable {
    private let identifier: ObjectIdentifier

    public init(_ type: Any.Type) {
        identifier = ObjectIdentifier(type)
    }

    init(identifier: ObjectIdentifier) {
        self.identifier = identifier
    }
}

public struct PreferenceDependencyKey: Hashable, Sendable {
    private let identifier: ObjectIdentifier

    public init(_ type: Any.Type) {
        identifier = ObjectIdentifier(type)
    }
}

public struct DuplicateIdentityDiagnostic: Error, Equatable, CustomStringConvertible {
    public let parent: StructuralIdentity?
    public let identity: StructuralIdentity
    public let firstIndex: Int
    public let duplicateIndex: Int

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

    public var description: String {
        let parentDescription = parent.map(String.init(describing:)) ?? "graph root"
        return "Duplicate structural identity \(identity) at child indexes \(firstIndex) and \(duplicateIndex) under \(parentDescription)."
    }
}
