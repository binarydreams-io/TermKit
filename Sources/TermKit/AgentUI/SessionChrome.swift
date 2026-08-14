// Design origin: ../../docs/design-origin.md

/// The lifecycle state of a task item.
public enum TodoState: String, Sendable, Hashable, CaseIterable {
    /// The task has not started.
    case pending
    /// The task is in progress.
    case inProgress
    /// The task completed.
    case completed
    /// The task was cancelled.
    case cancelled
}

/// A task item shown in the session interface.
public struct TodoItem<ID: Sendable & Hashable>: Sendable, Hashable {
    /// The stable task identifier.
    public var id: ID
    /// The task title.
    public var title: String
    /// Additional task details, if available.
    public var detail: String?
    /// The task state.
    public var state: TodoState

    /// Creates a task item.
    public init(id: ID, title: String, detail: String? = nil, state: TodoState = .pending) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }

    /// A Boolean value that indicates whether the task uses muted text.
    public var usesMutedText: Bool { state == .completed }
    /// A Boolean value that indicates whether the activity symbol animates.
    public var animatesActivitySymbol: Bool { state == .inProgress }
}

/// The placement of a session sidebar.
public enum SessionSidebarPlacement: String, Sendable, Hashable, CaseIterable {
    /// Places the sidebar in a fixed column.
    case fixedColumn
    /// Places the sidebar over trailing content.
    case trailingOverlay
}

/// Width rules for responsive session sidebar placement.
public struct SessionSidebarResponsivePolicy: Sendable, Hashable {
    /// The minimum terminal width for fixed-column placement.
    public var fixedColumnMinimumTerminalWidth: Int
    /// The preferred sidebar width.
    public var preferredColumnWidth: Int
    /// The minimum sidebar width.
    public var minimumColumnWidth: Int

    /// Creates a responsive sidebar policy.
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

    /// Returns the sidebar placement for a terminal width.
    /// - Complexity: O(1).
    public func placement(forTerminalWidth terminalWidth: Int) -> SessionSidebarPlacement {
        terminalWidth >= fixedColumnMinimumTerminalWidth ? .fixedColumn : .trailingOverlay
    }

    /// Returns the sidebar width for a terminal width.
    /// - Complexity: O(1).
    public func sidebarWidth(forTerminalWidth terminalWidth: Int) -> Int {
        min(preferredColumnWidth, max(0, terminalWidth))
    }
}

/// The content category of a sidebar section.
public enum SessionSidebarSectionKind: String, Sendable, Hashable, CaseIterable {
    /// Session metadata.
    case metadata
    /// Files associated with the session.
    case files
    /// Language service information.
    case languageServices
    /// External integrations.
    case integrations
    /// Session tasks.
    case todos
}

/// A titled section of session sidebar items.
public struct SessionSidebarSection<Item: Sendable & Hashable>: Sendable, Hashable {
    /// The section category.
    public var kind: SessionSidebarSectionKind
    /// The section title.
    public var title: String
    /// The section items.
    public var items: [Item]

    /// Creates a session sidebar section.
    public init(kind: SessionSidebarSectionKind, title: String, items: [Item]) {
        self.kind = kind
        self.title = title
        self.items = items
    }
}

/// Responsive sidebar content for a session.
public struct SessionSidebar<Item: Sendable & Hashable>: Sendable, Hashable {
    /// The sidebar sections.
    public var sections: [SessionSidebarSection<Item>]
    /// A Boolean value that indicates whether the overlay is presented.
    public var isOverlayPresented: Bool
    /// The responsive placement policy.
    public var policy: SessionSidebarResponsivePolicy

    /// Creates a session sidebar.
    public init(
        sections: [SessionSidebarSection<Item>],
        isOverlayPresented: Bool = false,
        policy: SessionSidebarResponsivePolicy = SessionSidebarResponsivePolicy()
    ) {
        self.sections = sections
        self.isOverlayPresented = isOverlayPresented
        self.policy = policy
    }

    /// Returns whether the sidebar is visible at a terminal width.
    /// - Complexity: O(1).
    public func isVisible(forTerminalWidth terminalWidth: Int) -> Bool {
        policy.placement(forTerminalWidth: terminalWidth) == .fixedColumn || isOverlayPresented
    }
}

/// Actions emitted by a session sidebar.
public struct SessionSidebarActions: Sendable {
    /// Dismisses the sidebar overlay.
    public var dismiss: @MainActor @Sendable () -> Void

    /// Creates session sidebar actions.
    public init(dismiss: @escaping @MainActor @Sendable () -> Void) {
        self.dismiss = dismiss
    }
}

/// The content category of a status field.
public enum AgentStatusFieldKind: String, Sendable, Hashable, CaseIterable {
    /// The active model.
    case model
    /// The active agent.
    case agent
    /// The session duration.
    case duration
    /// The context usage.
    case contextUsage
    /// The connection state.
    case connection
    /// Available keyboard shortcuts.
    case keyboardHints
}

/// One field in an agent status footer.
public struct AgentStatusField: Sendable, Hashable {
    /// The field category.
    public var kind: AgentStatusFieldKind
    /// The displayed text.
    public var text: String
    /// The retention priority when space is limited.
    public var priority: Int
    /// The minimum field width in cells.
    public var minimumWidth: Int

    /// Creates an agent status field.
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
    /// The status fields in display order.
    public var fields: [AgentStatusField]
    /// The spacing between fields in cells.
    public var fieldSpacing: Int

    /// Creates an agent status footer.
    public init(fields: [AgentStatusField], fieldSpacing: Int = 1) {
        precondition(fieldSpacing >= 0)
        self.fields = fields
        self.fieldSpacing = fieldSpacing
    }

    /// Returns the fields that fit within the available width.
    /// - Complexity: O(n^2), where n is the number of fields.
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
