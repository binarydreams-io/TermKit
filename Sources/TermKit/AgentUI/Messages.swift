/// The kind of content represented by an attachment.
public enum AttachmentKind: String, Sendable, Hashable, CaseIterable {
  /// A file attachment.
  case file
  /// A directory attachment.
  case directory
  /// An image attachment.
  case image
  /// A context attachment.
  case context
}

/// Compact attachment presentation with independent focus and remove actions.
public struct AttachmentChip<ID: Sendable & Hashable>: Sendable, Hashable {
  /// The stable attachment identifier.
  public var id: ID
  /// The attachment kind.
  public var kind: AttachmentKind
  /// The attachment name.
  public var name: String
  /// A Boolean value that indicates whether the chip has focus.
  public var isFocused: Bool

  /// Creates an attachment chip.
  public init(id: ID, kind: AttachmentKind, name: String, isFocused: Bool = false) {
    self.id = id
    self.kind = kind
    self.name = name
    self.isFocused = isFocused
  }
}

/// Actions emitted by an attachment chip.
public struct AttachmentChipActions<ID: Sendable>: Sendable {
  /// Focuses the specified attachment.
  public var focus: @MainActor @Sendable (_ id: ID) -> Void
  /// Removes the specified attachment.
  public var remove: @MainActor @Sendable (_ id: ID) -> Void

  /// Creates attachment chip actions.
  public init(
    focus: @escaping @MainActor @Sendable (_ id: ID) -> Void,
    remove: @escaping @MainActor @Sendable (_ id: ID) -> Void
  ) {
    self.focus = focus
    self.remove = remove
  }
}

/// Panel presentation for a user-authored message.
public struct UserMessageCard<Attachment: Sendable & Hashable>: Sendable, Hashable {
  /// The message text.
  public var text: String
  /// The message attachments.
  public var attachments: [Attachment]
  /// The display timestamp, if available.
  public var timestamp: String?
  /// A Boolean value that indicates whether the message is queued.
  public var isQueued: Bool
  /// A Boolean value that indicates whether the pointer hovers over the card.
  public var isHovered: Bool
  /// The semantic color of the agent rail.
  public var agentColor: SemanticColorRole

  /// Creates a user message card.
  public init(
    text: String,
    attachments: [Attachment] = [],
    timestamp: String? = nil,
    isQueued: Bool = false,
    isHovered: Bool = false,
    agentColor: SemanticColorRole = .accent
  ) {
    self.text = text
    self.attachments = attachments
    self.timestamp = timestamp
    self.isQueued = isQueued
    self.isHovered = isHovered
    self.agentColor = agentColor
  }

  /// The width of the agent rail in cells.
  public static var railWidth: Int {
    1
  }

  /// The horizontal content padding in cells.
  public static var horizontalPadding: Int {
    2
  }

  /// The vertical content padding in cells.
  public static var verticalPadding: Int {
    1
  }
}

/// Metadata displayed below an assistant message.
public struct AssistantMessageFooter: Sendable, Hashable {
  /// The agent mode label, if available.
  public var agentMode: String?
  /// The model label, if available.
  public var model: String?
  /// The response duration, if available.
  public var duration: TimeSpan?
  /// A Boolean value that indicates whether generation was interrupted.
  public var wasInterrupted: Bool

  /// Creates assistant message footer metadata.
  public init(
    agentMode: String? = nil,
    model: String? = nil,
    duration: TimeSpan? = nil,
    wasInterrupted: Bool = false
  ) {
    self.agentMode = agentMode
    self.model = model
    self.duration = duration
    self.wasInterrupted = wasInterrupted
  }
}

/// Open assistant composition. The generic values become concrete views during integration.
public struct AssistantMessage<Markdown: Sendable, Reasoning: Sendable, ToolActivity: Sendable, Diagnostic: Sendable>: Sendable {
  /// The rendered response content.
  public var markdown: [Markdown]
  /// The reasoning content.
  public var reasoning: [Reasoning]
  /// The tool activity content.
  public var toolActivity: [ToolActivity]
  /// The diagnostic content.
  public var diagnostics: [Diagnostic]
  /// The optional message footer.
  public var footer: AssistantMessageFooter?

  /// Creates an assistant message.
  public init(
    markdown: [Markdown] = [],
    reasoning: [Reasoning] = [],
    toolActivity: [ToolActivity] = [],
    diagnostics: [Diagnostic] = [],
    footer: AssistantMessageFooter? = nil
  ) {
    self.markdown = markdown
    self.reasoning = reasoning
    self.toolActivity = toolActivity
    self.diagnostics = diagnostics
    self.footer = footer
  }
}

/// The lifecycle phase of reasoning content.
public enum ReasoningPhase: String, Sendable, Hashable, CaseIterable {
  /// Reasoning is in progress.
  case running
  /// Reasoning is complete.
  case completed
}

/// Reasoning state whose collapsed form always occupies one row.
public struct ReasoningDisclosure<Body: Sendable & Hashable>: Sendable, Hashable {
  /// The reasoning phase.
  public var phase: ReasoningPhase
  /// A short reasoning summary, if available.
  public var summary: String?
  /// The disclosed reasoning body.
  public var body: Body
  /// The reasoning duration, if available.
  public var duration: TimeSpan?
  /// A Boolean value that indicates whether the body is expanded.
  public var isExpanded: Bool

  /// Creates a reasoning disclosure.
  public init(
    phase: ReasoningPhase,
    body: Body,
    summary: String? = nil,
    duration: TimeSpan? = nil,
    isExpanded: Bool = false
  ) {
    self.phase = phase
    self.summary = summary
    self.body = body
    self.duration = duration
    self.isExpanded = isExpanded
  }

  /// The height of the collapsed disclosure in cells.
  public var collapsedHeight: Int {
    1
  }

  /// The phase-dependent disclosure label.
  public var label: String {
    phase == .completed ? "Thought" : (summary ?? "Thinking")
  }
}

/// Actions emitted by a reasoning disclosure.
public struct ReasoningDisclosureActions: Sendable {
  /// Toggles the disclosed reasoning body.
  public var toggle: @MainActor @Sendable () -> Void

  /// Creates reasoning disclosure actions.
  public init(toggle: @escaping @MainActor @Sendable () -> Void) {
    self.toggle = toggle
  }
}

/// A transient status message.
public struct ToastPresentation: Sendable, Hashable {
  /// The toast kind.
  public var kind: ToastKind
  /// The message to display.
  public var message: String
  /// The display duration, if specified.
  public var duration: TimeSpan?

  /// Creates a toast presentation.
  public init(kind: ToastKind, message: String, duration: TimeSpan? = nil) {
    self.kind = kind
    self.message = message
    self.duration = duration
  }
}
