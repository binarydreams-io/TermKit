public struct FocusID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A focus identifier must not be empty.")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct FocusScopeID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A focus scope identifier must not be empty.")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct FocusTarget: Sendable, Hashable {
    public var id: FocusID
    public var scopeID: FocusScopeID?
    public var isEnabled: Bool
    public var order: Int

    public init(id: FocusID, scopeID: FocusScopeID? = nil, isEnabled: Bool = true, order: Int = 0) {
        self.id = id
        self.scopeID = scopeID
        self.isEnabled = isEnabled
        self.order = order
    }
}

public struct FocusScope: Sendable, Hashable {
    public var id: FocusScopeID
    public var trapsFocus: Bool

    public init(id: FocusScopeID, trapsFocus: Bool = false) {
        self.id = id
        self.trapsFocus = trapsFocus
    }
}

@MainActor
public final class FocusManager {
    public private(set) var focusedID: FocusID?
    public var activeScopeID: FocusScopeID? { scopeStack.last?.scope.id }

    private struct ActiveScope {
        var scope: FocusScope
        var restoreID: FocusID?
    }

    private var targets: [FocusID: FocusTarget] = [:]
    private var registrationOrder: [FocusID] = []
    private var scopeStack: [ActiveScope] = []

    public init() {}

    public func register(_ target: FocusTarget) {
        if targets[target.id] == nil { registrationOrder.append(target.id) }
        targets[target.id] = target
        if focusedID == target.id, target.isEnabled == false {
            focusedID = eligibleTargets().first?.id
        }
    }

    public func unregister(_ id: FocusID) {
        targets.removeValue(forKey: id)
        registrationOrder.removeAll { $0 == id }
        if focusedID == id { focusedID = eligibleTargets().first?.id }
    }

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

    public func activateScope(_ scope: FocusScope, initialFocus: FocusID? = nil) {
        scopeStack.append(ActiveScope(scope: scope, restoreID: focusedID))
        if let initialFocus, requestFocus(initialFocus) { return }
        focusedID = eligibleTargets().first?.id
    }

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
