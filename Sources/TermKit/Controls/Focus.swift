/// A stable identifier for a focus target.
public struct FocusID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    /// The identifier's string value.
    public var rawValue: String

    /// Creates a focus identifier from a nonempty string.
    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A focus identifier must not be empty.")
        self.rawValue = rawValue
    }

    /// Creates a focus identifier from a string literal.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// A stable identifier for a focus scope.
public struct FocusScopeID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    /// The identifier's string value.
    public var rawValue: String

    /// Creates a focus scope identifier from a nonempty string.
    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A focus scope identifier must not be empty.")
        self.rawValue = rawValue
    }

    /// Creates a focus scope identifier from a string literal.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// A registered destination for keyboard focus.
public struct FocusTarget: Sendable, Hashable {
    /// The target identifier.
    public var id: FocusID
    /// The containing focus scope, if any.
    public var scopeID: FocusScopeID?
    /// A value that indicates whether the target can receive focus.
    public var isEnabled: Bool
    /// The explicit traversal order.
    public var order: Int

    /// Creates a focus target.
    public init(id: FocusID, scopeID: FocusScopeID? = nil, isEnabled: Bool = true, order: Int = 0) {
        self.id = id
        self.scopeID = scopeID
        self.isEnabled = isEnabled
        self.order = order
    }
}

/// A focus scope that can optionally trap traversal.
public struct FocusScope: Sendable, Hashable {
    /// The scope identifier.
    public var id: FocusScopeID
    /// A value that indicates whether focus stays within the scope.
    public var trapsFocus: Bool

    /// Creates a focus scope.
    public init(id: FocusScopeID, trapsFocus: Bool = false) {
        self.id = id
        self.trapsFocus = trapsFocus
    }
}

/// Registers focus targets and manages focus traversal and scopes.
@MainActor
public final class FocusManager {
    /// The currently focused target identifier.
    public private(set) var focusedID: FocusID?
    /// The active focus scope identifier.
    public var activeScopeID: FocusScopeID? { scopeStack.last?.scope.id }

    private struct ActiveScope {
        var scope: FocusScope
        var restoreID: FocusID?
    }

    private var targets: [FocusID: FocusTarget] = [:]
    private var registrationOrder: [FocusID] = []
    private var scopeStack: [ActiveScope] = []

    /// Creates an empty focus manager.
    public init() {}

    /// Registers or updates a focus target.
    /// - Complexity: O(n) when focus must move, otherwise O(1) on average.
    public func register(_ target: FocusTarget) {
        if targets[target.id] == nil { registrationOrder.append(target.id) }
        targets[target.id] = target
        if focusedID == target.id, target.isEnabled == false {
            focusedID = eligibleTargets().first?.id
        }
    }

    /// Removes a focus target.
    /// - Complexity: O(n), where n is the target count.
    public func unregister(_ id: FocusID) {
        targets.removeValue(forKey: id)
        registrationOrder.removeAll { $0 == id }
        if focusedID == id { focusedID = eligibleTargets().first?.id }
    }

    /// Requests focus for a target or clears focus with `nil`.
    /// - Complexity: O(1) on average.
    @discardableResult
    public func requestFocus(_ id: FocusID?) -> Bool {
        guard let id else {
            focusedID = nil
            return true
        }
        guard let target = targets[id], isEligible(target) else { return false }
        focusedID = id
        return true
    }

    /// Moves focus through eligible targets.
    /// - Complexity: O(n log n), where n is the target count.
    @discardableResult
    public func moveFocus(forward: Bool = true) -> FocusID? {
        let eligible = eligibleTargets()
        guard eligible.isEmpty == false else {
            focusedID = nil
            return nil
        }
        guard let focusedID, let index = eligible.firstIndex(where: { $0.id == focusedID }) else {
            self.focusedID = forward ? eligible.first?.id : eligible.last?.id
            return self.focusedID
        }
        let delta = forward ? 1 : -1
        let target = (index + delta + eligible.count) % eligible.count
        self.focusedID = eligible[target].id
        return self.focusedID
    }

    /// Pushes and activates a focus scope.
    /// - Complexity: O(n log n), where n is the target count.
    public func activateScope(_ scope: FocusScope, initialFocus: FocusID? = nil) {
        scopeStack.append(ActiveScope(scope: scope, restoreID: focusedID))
        if let initialFocus, requestFocus(initialFocus) { return }
        focusedID = eligibleTargets().first?.id
    }

    /// Removes the active scope and restores eligible focus.
    /// - Complexity: O(n log n), where n is the target count.
    @discardableResult
    public func deactivateScope(_ id: FocusScopeID) -> Bool {
        guard scopeStack.last?.scope.id == id, let removed = scopeStack.popLast() else { return false }
        if let restoreID = removed.restoreID, requestFocus(restoreID) { return true }
        focusedID = eligibleTargets().first?.id
        return true
    }

    private func eligibleTargets() -> [FocusTarget] {
        let positions = Dictionary(uniqueKeysWithValues: registrationOrder.enumerated().map { ($0.element, $0.offset) })
        return targets.values
            .filter { isEligible($0) }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return positions[$0.id, default: .max] < positions[$1.id, default: .max]
            }
    }

    private func isEligible(_ target: FocusTarget) -> Bool {
        guard target.isEnabled else { return false }
        guard let scope = scopeStack.last?.scope, scope.trapsFocus else { return true }
        return target.scopeID == scope.id
    }
}
