// Interaction concepts adapted from OpenCode; no OpenCode source code was copied.
// Design origin: ../../docs/design-origin.md

public enum ToolCallState: String, Sendable, Hashable, CaseIterable {
    case pending
    case running
    case completed
    case denied
    case failed
}

/// One tool activity row with a stable icon column.
public struct ToolCallRow<ID: Sendable & Hashable>: Sendable, Hashable {
    public var id: ID
    public var label: String
    public var state: ToolCallState
    public var errorBody: String?
    public var isErrorExpanded: Bool
    public var iconColumnWidth: Int

    public init(
        id: ID,
        label: String,
        state: ToolCallState,
        errorBody: String? = nil,
        isErrorExpanded: Bool = false,
        iconColumnWidth: Int = 2
    ) {
        precondition(iconColumnWidth >= 1)
        self.id = id
        self.label = label
        self.state = state
        self.errorBody = errorBody
        self.isErrorExpanded = isErrorExpanded
        self.iconColumnWidth = iconColumnWidth
    }

    public func labelWidth(in availableWidth: Int) -> Int {
        max(0, availableWidth - iconColumnWidth)
    }

    public var revealsError: Bool {
        state == .failed && isErrorExpanded && errorBody != nil
    }
}

public struct ToolCallRowActions<ID: Sendable>: Sendable {
    public var toggleFailure: @MainActor @Sendable (ID) -> Void

    public init(toggleFailure: @escaping @MainActor @Sendable (ID) -> Void) {
        self.toggleFailure = toggleFailure
    }
}

public enum ToolResultPresentation: String, Sendable, Hashable, CaseIterable {
    case inline
    case panel
}

public struct ToolResultPanel<Content: Sendable & Hashable>: Sendable, Hashable {
    public var title: String
    public var content: Content
    public var presentation: ToolResultPresentation

    public init(title: String, content: Content, presentation: ToolResultPresentation = .panel) {
        self.title = title
        self.content = content
        self.presentation = presentation
    }

    public var isVisibleAsPanel: Bool { presentation == .panel }
}

/// Width-sensitive default limits for collapsed shell output.
public struct ShellResultCollapsePolicy: Sendable, Hashable {
    public var narrowWidth: Int
    public var narrowLineLimit: Int
    public var regularLineLimit: Int

    public init(narrowWidth: Int = 80, narrowLineLimit: Int = 4, regularLineLimit: Int = 8) {
        precondition(narrowWidth >= 0 && narrowLineLimit >= 0 && regularLineLimit >= 0)
        self.narrowWidth = narrowWidth
        self.narrowLineLimit = narrowLineLimit
        self.regularLineLimit = regularLineLimit
    }

    public func lineLimit(viewportWidth: Int, lineCount: Int) -> Int? {
        precondition(viewportWidth >= 0 && lineCount >= 0)
        let limit = viewportWidth < narrowWidth ? narrowLineLimit : regularLineLimit
        return lineCount > limit ? limit : nil
    }
}

/// Shell output state. Expansion does not replace the selection or scroll anchor.
public struct ShellResult: Sendable, Hashable {
    public var command: String
    public var workingDirectory: String?
    public var output: String
    public var isRunning: Bool
    public var exitCode: Int?
    public var isExpanded: Bool
    public var selection: Range<Int>?
    public var scrollAnchorLine: Int?

    public init(
        command: String,
        workingDirectory: String? = nil,
        output: String = "",
        isRunning: Bool = false,
        exitCode: Int? = nil,
        isExpanded: Bool = false,
        selection: Range<Int>? = nil,
        scrollAnchorLine: Int? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.output = output
        self.isRunning = isRunning
        self.exitCode = exitCode
        self.isExpanded = isExpanded
        self.selection = selection
        self.scrollAnchorLine = scrollAnchorLine
    }

    public var hasFailed: Bool { exitCode.map { $0 != 0 } ?? false }

    public mutating func toggleExpansion() {
        isExpanded.toggle()
    }

    public func visibleLineLimit(viewportWidth: Int, policy: ShellResultCollapsePolicy = ShellResultCollapsePolicy()) -> Int? {
        guard isExpanded == false else { return nil }
        let lineCount = output.split(separator: "\n", omittingEmptySubsequences: false).count
        return policy.lineLimit(viewportWidth: viewportWidth, lineCount: lineCount)
    }
}

public struct ShellResultActions: Sendable {
    public var toggleExpansion: @MainActor @Sendable () -> Void

    public init(toggleExpansion: @escaping @MainActor @Sendable () -> Void) {
        self.toggleExpansion = toggleExpansion
    }
}
