public enum DiagnosticSeverity: Int, Sendable, Hashable, CaseIterable, Comparable {
    case information
    case warning
    case error

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DiagnosticPresentation<ID: Sendable & Hashable>: Sendable, Hashable {
    public var id: ID
    public var severity: DiagnosticSeverity
    public var path: String?
    public var line: Int?
    public var column: Int?
    public var message: String

    public init(
        id: ID,
        severity: DiagnosticSeverity,
        path: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        message: String
    ) {
        precondition(line.map { $0 >= 1 } ?? true)
        precondition(column.map { $0 >= 1 } ?? true)
        self.id = id
        self.severity = severity
        self.path = path
        self.line = line
        self.column = column
        self.message = message
    }
}

public enum DiagnosticsListMode: String, Sendable, Hashable, CaseIterable {
    case inline
    case block
}

public struct DiagnosticsList<ID: Sendable & Hashable>: Sendable, Hashable {
    public var diagnostics: [DiagnosticPresentation<ID>]
    public var mode: DiagnosticsListMode

    public init(diagnostics: [DiagnosticPresentation<ID>], mode: DiagnosticsListMode = .block) {
        self.diagnostics = diagnostics
        self.mode = mode
    }

    public var highestSeverity: DiagnosticSeverity? {
        diagnostics.map(\.severity).max()
    }

    public var inlineSummary: String? {
        guard diagnostics.isEmpty == false else { return nil }
        let errorCount = diagnostics.count { $0.severity == .error }
        let warningCount = diagnostics.count { $0.severity == .warning }
        if errorCount > 0 { return "\(errorCount) error\(errorCount == 1 ? "" : "s")" }
        if warningCount > 0 { return "\(warningCount) warning\(warningCount == 1 ? "" : "s")" }
        return "\(diagnostics.count) diagnostic\(diagnostics.count == 1 ? "" : "s")"
    }
}

public struct DiagnosticsListActions<ID: Sendable>: Sendable {
    public var navigate: @MainActor @Sendable (ID) -> Void

    public init(navigate: @escaping @MainActor @Sendable (ID) -> Void) {
        self.navigate = navigate
    }
}

public struct DiagnosticsListState: Sendable, Hashable {
    public var focusedIndex: Int

    public init(focusedIndex: Int = 0) {
        precondition(focusedIndex >= 0)
        self.focusedIndex = focusedIndex
    }
}
