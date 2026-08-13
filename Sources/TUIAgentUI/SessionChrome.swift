// Interaction concepts adapted from OpenCode; no OpenCode source code was copied.
// Design origin: ../../docs/design-origin.md

import TUIFoundation

public enum TodoState: String, Sendable, Hashable, CaseIterable {
    case pending
    case inProgress
    case completed
    case cancelled
}

public struct TodoItem<ID: Sendable & Hashable>: Sendable, Hashable {
    public var id: ID
    public var title: String
    public var detail: String?
    public var state: TodoState

    public init(id: ID, title: String, detail: String? = nil, state: TodoState = .pending) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }

    public var usesMutedText: Bool { state == .completed }
    public var animatesActivitySymbol: Bool { state == .inProgress }
}

public enum SessionSidebarPlacement: String, Sendable, Hashable, CaseIterable {
    case fixedColumn
    case trailingOverlay
}

public struct SessionSidebarResponsivePolicy: Sendable, Hashable {
    public var fixedColumnMinimumTerminalWidth: Int
    public var preferredColumnWidth: Int
    public var minimumColumnWidth: Int

    public init(
        fixedColumnMinimumTerminalWidth: Int = 100,
        preferredColumnWidth: Int = 32,
        minimumColumnWidth: Int = 24
    ) {
        precondition(fixedColumnMinimumTerminalWidth >= 0)
        precondition(preferredColumnWidth >= minimumColumnWidth && minimumColumnWidth >= 0)
        self.fixedColumnMinimumTerminalWidth = fixedColumnMinimumTerminalWidth
        self.preferredColumnWidth = preferredColumnWidth
        self.minimumColumnWidth = minimumColumnWidth
    }

    public func placement(forTerminalWidth terminalWidth: Int) -> SessionSidebarPlacement {
        terminalWidth >= fixedColumnMinimumTerminalWidth ? .fixedColumn : .trailingOverlay
    }

    public func sidebarWidth(forTerminalWidth terminalWidth: Int) -> Int {
        min(preferredColumnWidth, max(0, terminalWidth))
    }
}

public enum SessionSidebarSectionKind: String, Sendable, Hashable, CaseIterable {
    case metadata
    case files
    case languageServices
    case integrations
    case todos
}

public struct SessionSidebarSection<Item: Sendable & Hashable>: Sendable, Hashable {
    public var kind: SessionSidebarSectionKind
    public var title: String
    public var items: [Item]

    public init(kind: SessionSidebarSectionKind, title: String, items: [Item]) {
        self.kind = kind
        self.title = title
        self.items = items
    }
}

public struct SessionSidebar<Item: Sendable & Hashable>: Sendable, Hashable {
    public var sections: [SessionSidebarSection<Item>]
    public var isOverlayPresented: Bool
    public var policy: SessionSidebarResponsivePolicy

    public init(
        sections: [SessionSidebarSection<Item>],
        isOverlayPresented: Bool = false,
        policy: SessionSidebarResponsivePolicy = SessionSidebarResponsivePolicy()
    ) {
        self.sections = sections
        self.isOverlayPresented = isOverlayPresented
        self.policy = policy
    }

    public func isVisible(forTerminalWidth terminalWidth: Int) -> Bool {
        policy.placement(forTerminalWidth: terminalWidth) == .fixedColumn || isOverlayPresented
    }
}

public struct SessionSidebarActions: Sendable {
    public var dismiss: @MainActor @Sendable () -> Void

    public init(dismiss: @escaping @MainActor @Sendable () -> Void) {
        self.dismiss = dismiss
    }
}

public enum AgentStatusFieldKind: String, Sendable, Hashable, CaseIterable {
    case model
    case agent
    case duration
    case contextUsage
    case connection
    case keyboardHints
}

public struct AgentStatusField: Sendable, Hashable {
    public var kind: AgentStatusFieldKind
    public var text: String
    public var priority: Int
    public var minimumWidth: Int

    public init(kind: AgentStatusFieldKind, text: String, priority: Int, minimumWidth: Int? = nil) {
        precondition(minimumWidth.map { $0 >= 0 } ?? true)
        self.kind = kind
        self.text = text
        self.priority = priority
        self.minimumWidth = minimumWidth ?? TerminalWidth.width(of: text)
    }
}

/// One-row footer that removes the lowest-priority fields until it fits.
public struct AgentStatusFooter: Sendable, Hashable {
    public var fields: [AgentStatusField]
    public var fieldSpacing: Int

    public init(fields: [AgentStatusField], fieldSpacing: Int = 1) {
        precondition(fieldSpacing >= 0)
        self.fields = fields
        self.fieldSpacing = fieldSpacing
    }

    public func visibleFields(availableWidth: Int) -> [AgentStatusField] {
        precondition(availableWidth >= 0)
        var indexedFields = Array(fields.enumerated())
        while requiredWidth(for: indexedFields.map(\.element)) > availableWidth, indexedFields.isEmpty == false {
            let removalIndex = indexedFields.indices.min { lhs, rhs in
                let left = indexedFields[lhs]
                let right = indexedFields[rhs]
                return left.element.priority == right.element.priority
                    ? left.offset > right.offset
                    : left.element.priority < right.element.priority
            }
            if let removalIndex { indexedFields.remove(at: removalIndex) }
        }
        return indexedFields.map(\.element)
    }

    private func requiredWidth(for fields: [AgentStatusField]) -> Int {
        fields.reduce(0) { $0 + $1.minimumWidth } + max(0, fields.count - 1) * fieldSpacing
    }
}
