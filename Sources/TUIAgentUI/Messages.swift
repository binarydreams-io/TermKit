import TUIFoundation
import TUIDesign

public enum AttachmentKind: String, Sendable, Hashable, CaseIterable {
    case file
    case directory
    case image
    case context
}

/// Compact attachment presentation with independent focus and remove actions.
public struct AttachmentChip<ID: Sendable & Hashable>: Sendable, Hashable {
    public var id: ID
    public var kind: AttachmentKind
    public var name: String
    public var isFocused: Bool

    public init(id: ID, kind: AttachmentKind, name: String, isFocused: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isFocused = isFocused
    }
}

public struct AttachmentChipActions<ID: Sendable>: Sendable {
    public var focus: @MainActor @Sendable (ID) -> Void
    public var remove: @MainActor @Sendable (ID) -> Void

    public init(
        focus: @escaping @MainActor @Sendable (ID) -> Void,
        remove: @escaping @MainActor @Sendable (ID) -> Void
    ) {
        self.focus = focus
        self.remove = remove
    }
}

/// Panel presentation for a user-authored message.
public struct UserMessageCard<Attachment: Sendable & Hashable>: Sendable, Hashable {
    public var text: String
    public var attachments: [Attachment]
    public var timestamp: String?
    public var isQueued: Bool
    public var isHovered: Bool
    public var agentColor: SemanticColorRole

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

    public static var railWidth: Int { 1 }
    public static var horizontalPadding: Int { 2 }
    public static var verticalPadding: Int { 1 }
}

public struct AssistantMessageFooter: Sendable, Hashable {
    public var agentMode: String?
    public var model: String?
    public var duration: TUIDuration?
    public var wasInterrupted: Bool

    public init(
        agentMode: String? = nil,
        model: String? = nil,
        duration: TUIDuration? = nil,
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
    public var markdown: [Markdown]
    public var reasoning: [Reasoning]
    public var toolActivity: [ToolActivity]
    public var diagnostics: [Diagnostic]
    public var footer: AssistantMessageFooter?

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

public enum ReasoningPhase: String, Sendable, Hashable, CaseIterable {
    case running
    case completed
}

/// Reasoning state whose collapsed form always occupies one row.
public struct ReasoningDisclosure<Body: Sendable & Hashable>: Sendable, Hashable {
    public var phase: ReasoningPhase
    public var summary: String?
    public var body: Body
    public var duration: TUIDuration?
    public var isExpanded: Bool

    public init(
        phase: ReasoningPhase,
        summary: String? = nil,
        body: Body,
        duration: TUIDuration? = nil,
        isExpanded: Bool = false
    ) {
        self.phase = phase
        self.summary = summary
        self.body = body
        self.duration = duration
        self.isExpanded = isExpanded
    }

    public var collapsedHeight: Int { 1 }
    public var label: String { phase == .completed ? "Thought" : (summary ?? "Thinking") }
}

public struct ReasoningDisclosureActions: Sendable {
    public var toggle: @MainActor @Sendable () -> Void

    public init(toggle: @escaping @MainActor @Sendable () -> Void) {
        self.toggle = toggle
    }
}

public enum ToastKind: String, Sendable, Hashable, CaseIterable {
    case information
    case success
    case warning
    case failure
}

public struct ToastPresentation: Sendable, Hashable {
    public var kind: ToastKind
    public var message: String
    public var duration: TUIDuration?

    public init(kind: ToastKind, message: String, duration: TUIDuration? = nil) {
        self.kind = kind
        self.message = message
        self.duration = duration
    }
}
