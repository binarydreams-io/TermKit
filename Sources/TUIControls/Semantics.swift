import TUIFoundation

public struct SemanticID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A semantic identifier must not be empty.")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public enum SemanticRole: String, Sendable, Hashable {
    case text
    case button
    case textEditor
    case list
    case listItem
    case scrollView
    case dialog
    case menu
    case menuItem
    case group
    case status
    case progressIndicator
}

public struct SemanticState: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let selected = SemanticState(rawValue: 1 << 0)
    public static let current = SemanticState(rawValue: 1 << 1)
    public static let disabled = SemanticState(rawValue: 1 << 2)
    public static let focused = SemanticState(rawValue: 1 << 3)
    public static let expanded = SemanticState(rawValue: 1 << 4)
    public static let busy = SemanticState(rawValue: 1 << 5)
    public static let checked = SemanticState(rawValue: 1 << 6)
    public static let hovered = SemanticState(rawValue: 1 << 7)
    public static let modal = SemanticState(rawValue: 1 << 8)
}

public enum SemanticAction: String, Sendable, Hashable {
    case activate
    case focus
    case dismiss
    case submit
    case increment
    case decrement
    case setValue
    case scrollForward
    case scrollBackward
}

public struct SemanticNode: Sendable, Hashable {
    public var id: SemanticID
    public var role: SemanticRole
    public var label: String
    public var value: String?
    public var state: SemanticState
    public var actions: Set<SemanticAction>
    public var frame: CellRect?
    public var children: [SemanticNode]

    public init(
        id: SemanticID,
        role: SemanticRole,
        label: String = "",
        value: String? = nil,
        state: SemanticState = [],
        actions: Set<SemanticAction> = [],
        frame: CellRect? = nil,
        children: [SemanticNode] = []
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.state = state
        self.actions = actions
        self.frame = frame
        self.children = children
    }

    public func node(withID id: SemanticID) -> SemanticNode? {
        if self.id == id { return self }
        for child in children {
            if let match = child.node(withID: id) { return match }
        }
        return nil
    }

    public var depthFirstNodes: [SemanticNode] {
        [self] + children.flatMap(\.depthFirstNodes)
    }
}

public struct SemanticTree: Sendable, Hashable {
    public var roots: [SemanticNode]

    public init(roots: [SemanticNode] = []) {
        self.roots = roots
    }

    public func node(withID id: SemanticID) -> SemanticNode? {
        roots.lazy.compactMap { $0.node(withID: id) }.first
    }

    public func nodes(withRole role: SemanticRole) -> [SemanticNode] {
        roots.flatMap(\.depthFirstNodes).filter { $0.role == role }
    }
}
