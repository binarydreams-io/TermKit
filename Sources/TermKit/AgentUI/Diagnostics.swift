/// The severity of a diagnostic message.
public enum DiagnosticSeverity: Int, Sendable, Hashable, CaseIterable, Comparable {
  /// An informational diagnostic.
  case information
  /// A diagnostic that reports a potential problem.
  case warning
  /// A diagnostic that reports an error.
  case error

  /// Returns whether the left severity is lower than the right severity.
  /// - Complexity: O(1).
  public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// A diagnostic and its optional source location.
public struct DiagnosticPresentation<ID: Sendable & Hashable>: Sendable, Hashable {
  /// The stable diagnostic identifier.
  public var id: ID
  /// The diagnostic severity.
  public var severity: DiagnosticSeverity
  /// The source path, if available.
  public var path: String?
  /// The one-based source line, if available.
  public var line: Int?
  /// The one-based source column, if available.
  public var column: Int?
  /// The diagnostic message.
  public var message: String

  /// Creates a diagnostic presentation.
  public init(
    id: ID,
    severity: DiagnosticSeverity,
    message: String,
    path: String? = nil,
    line: Int? = nil,
    column: Int? = nil
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

/// The layout mode for a diagnostics list.
public enum DiagnosticsListMode: String, Sendable, Hashable, CaseIterable {
  /// Displays a compact summary.
  case inline
  /// Displays each diagnostic as a separate row.
  case block
}

/// A collection of diagnostics with a presentation mode.
public struct DiagnosticsList<ID: Sendable & Hashable>: Sendable, Hashable {
  /// The diagnostics to present.
  public var diagnostics: [DiagnosticPresentation<ID>]
  /// The list presentation mode.
  public var mode: DiagnosticsListMode

  /// Creates a diagnostics list.
  public init(diagnostics: [DiagnosticPresentation<ID>], mode: DiagnosticsListMode = .block) {
    self.diagnostics = diagnostics
    self.mode = mode
  }

  /// The highest severity in the list, or `nil` when the list is empty.
  /// - Complexity: O(n), where n is the number of diagnostics.
  public var highestSeverity: DiagnosticSeverity? {
    diagnostics.map(\.severity).max()
  }

  /// A count summary for inline presentation.
  /// - Complexity: O(n), where n is the number of diagnostics.
  public var inlineSummary: String? {
    guard diagnostics.isEmpty == false else { return nil }
    let errorCount = diagnostics.count { $0.severity == .error }
    let warningCount = diagnostics.count { $0.severity == .warning }
    if errorCount > 0 {
      return "\(errorCount) error\(errorCount == 1 ? "" : "s")"
    }
    if warningCount > 0 {
      return "\(warningCount) warning\(warningCount == 1 ? "" : "s")"
    }
    return "\(diagnostics.count) diagnostic\(diagnostics.count == 1 ? "" : "s")"
  }
}

/// Actions emitted by a diagnostics list.
public struct DiagnosticsListActions<ID: Sendable>: Sendable {
  /// Navigates to the diagnostic with the specified identifier.
  public var navigate: @MainActor @Sendable (_ id: ID) -> Void

  /// Creates diagnostics list actions.
  public init(navigate: @escaping @MainActor @Sendable (_ id: ID) -> Void) {
    self.navigate = navigate
  }
}

/// Focus state for a diagnostics list.
public struct DiagnosticsListState: Sendable, Hashable {
  /// The index of the focused diagnostic.
  public var focusedIndex: Int

  /// Creates diagnostics list state.
  public init(focusedIndex: Int = 0) {
    precondition(focusedIndex >= 0)
    self.focusedIndex = focusedIndex
  }
}
