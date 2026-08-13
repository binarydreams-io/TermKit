public enum ShowcaseComponent: String, Sendable, Hashable, CaseIterable {
    case prompt
    case commandPalette
    case messages
    case reasoning
    case tools
    case diff
    case permissions
    case questions
    case toast
    case sidebar
}

public struct ShowcaseEntry: Sendable, Hashable {
    public var component: ShowcaseComponent
    public var title: String

    public init(component: ShowcaseComponent, title: String) {
        self.component = component
        self.title = title
    }
}

/// Canonical inventory for the agent UI showcase.
public struct ShowcaseCatalog: Sendable, Hashable {
    public var entries: [ShowcaseEntry]

    public init(entries: [ShowcaseEntry] = ShowcaseCatalog.requiredEntries) {
        self.entries = entries
    }

    public var coveredComponents: Set<ShowcaseComponent> {
        Set(entries.map(\.component))
    }

    public var missingRequiredComponents: Set<ShowcaseComponent> {
        Set(ShowcaseComponent.allCases).subtracting(coveredComponents)
    }

    public static let requiredEntries: [ShowcaseEntry] = [
        ShowcaseEntry(component: .prompt, title: "Prompt"),
        ShowcaseEntry(component: .commandPalette, title: "Command palette"),
        ShowcaseEntry(component: .messages, title: "Messages"),
        ShowcaseEntry(component: .reasoning, title: "Reasoning"),
        ShowcaseEntry(component: .tools, title: "Tools"),
        ShowcaseEntry(component: .diff, title: "Diff"),
        ShowcaseEntry(component: .permissions, title: "Permissions"),
        ShowcaseEntry(component: .questions, title: "Questions"),
        ShowcaseEntry(component: .toast, title: "Toast"),
        ShowcaseEntry(component: .sidebar, title: "Sidebar"),
    ]
}
