// Design origin: ../../docs/design-origin.md

/// The execution state of a tool call.
public enum ToolCallState: String, Sendable, Hashable, CaseIterable {
  /// The tool call is waiting to start.
  case pending
  /// The tool call is running.
  case running
  /// The tool call completed successfully.
  case completed
  /// The user denied the tool call.
  case denied
  /// The tool call failed.
  case failed
}

/// One tool activity row with a stable icon column.
public struct ToolCallRow<ID: Sendable & Hashable>: Sendable, Hashable {
  /// The stable tool call identifier.
  public var id: ID
  /// The display label.
  public var label: String
  /// The execution state.
  public var state: ToolCallState
  /// The failure details, if available.
  public var errorBody: String?
  /// A Boolean value that indicates whether failure details are expanded.
  public var isErrorExpanded: Bool
  /// The width of the icon column in cells.
  public var iconColumnWidth: Int

  /// Creates a tool call row.
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

  /// Returns the width available for the label.
  /// - Complexity: O(1).
  public func labelWidth(in availableWidth: Int) -> Int {
    max(0, availableWidth - iconColumnWidth)
  }

  /// A Boolean value that indicates whether the row reveals its error details.
  /// - Complexity: O(1).
  public var revealsError: Bool {
    state == .failed && isErrorExpanded && errorBody != nil
  }
}

/// Actions emitted by a tool call row.
public struct ToolCallRowActions<ID: Sendable>: Sendable {
  /// Toggles failure details for the specified tool call.
  public var toggleFailure: @MainActor @Sendable (_ id: ID) -> Void

  /// Creates tool call row actions.
  public init(toggleFailure: @escaping @MainActor @Sendable (_ id: ID) -> Void) {
    self.toggleFailure = toggleFailure
  }
}

/// The presentation style of a tool result.
public enum ToolResultPresentation: String, Sendable, Hashable, CaseIterable {
  /// Displays the result within surrounding content.
  case inline
  /// Displays the result in a panel.
  case panel
}

/// A tool result with presentation metadata.
public struct ToolResultPanel<Content: Sendable & Hashable>: Sendable, Hashable {
  /// The panel title.
  public var title: String
  /// The result content.
  public var content: Content
  /// The result presentation style.
  public var presentation: ToolResultPresentation

  /// Creates a tool result panel.
  public init(title: String, content: Content, presentation: ToolResultPresentation = .panel) {
    self.title = title
    self.content = content
    self.presentation = presentation
  }

  /// A Boolean value that indicates whether the result uses panel presentation.
  /// - Complexity: O(1).
  public var isVisibleAsPanel: Bool {
    presentation == .panel
  }
}

/// Width-sensitive default limits for collapsed shell output.
public struct ShellResultCollapsePolicy: Sendable, Hashable {
  /// The width below which the narrow limit applies.
  public var narrowWidth: Int
  /// The collapsed line limit for narrow viewports.
  public var narrowLineLimit: Int
  /// The collapsed line limit for regular viewports.
  public var regularLineLimit: Int

  /// Creates a shell result collapse policy.
  public init(narrowWidth: Int = 80, narrowLineLimit: Int = 4, regularLineLimit: Int = 8) {
    precondition(narrowWidth >= 0 && narrowLineLimit >= 0 && regularLineLimit >= 0)
    self.narrowWidth = narrowWidth
    self.narrowLineLimit = narrowLineLimit
    self.regularLineLimit = regularLineLimit
  }

  /// Returns the line limit when the output requires collapsing.
  /// - Complexity: O(1).
  public func lineLimit(viewportWidth: Int, lineCount: Int) -> Int? {
    precondition(viewportWidth >= 0 && lineCount >= 0)
    let limit = viewportWidth < narrowWidth ? narrowLineLimit : regularLineLimit
    return lineCount > limit ? limit : nil
  }
}

/// Shell output state. Expansion does not replace the selection or scroll anchor.
public struct ShellResult: Sendable, Hashable {
  /// The executed command.
  public var command: String
  /// The working directory, if available.
  public var workingDirectory: String?
  /// The command output.
  public var output: String
  /// A Boolean value that indicates whether the command is running.
  public var isRunning: Bool
  /// The process exit code, if available.
  public var exitCode: Int?
  /// A Boolean value that indicates whether all output is visible.
  public var isExpanded: Bool
  /// The selected character range, if any.
  public var selection: Range<Int>?
  /// The line that anchors scrolling, if any.
  public var scrollAnchorLine: Int?

  /// Creates shell result state.
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

  /// A Boolean value that indicates whether the command failed.
  /// - Complexity: O(1).
  public var hasFailed: Bool {
    exitCode.map { $0 != 0 } ?? false
  }

  /// Toggles expanded output.
  /// - Complexity: O(1).
  public mutating func toggleExpansion() {
    isExpanded.toggle()
  }

  /// Returns the collapsed output limit for a viewport.
  /// - Complexity: O(n), where n is the output length.
  public func visibleLineLimit(viewportWidth: Int, policy: ShellResultCollapsePolicy = ShellResultCollapsePolicy()) -> Int? {
    guard isExpanded == false else { return nil }
    let lineCount = output.split(separator: "\n", omittingEmptySubsequences: false).count
    return policy.lineLimit(viewportWidth: viewportWidth, lineCount: lineCount)
  }
}

/// Actions emitted by a shell result.
public struct ShellResultActions: Sendable {
  /// Toggles expanded output.
  public var toggleExpansion: @MainActor @Sendable () -> Void

  /// Creates shell result actions.
  public init(toggleExpansion: @escaping @MainActor @Sendable () -> Void) {
    self.toggleExpansion = toggleExpansion
  }
}
