/// A command displayed by a command palette.
public struct PaletteCommand<ID: Hashable & Sendable>: Sendable, Identifiable {
    /// The stable command identifier.
    public var id: ID
    /// The command title.
    public var title: String
    /// Optional detail text.
    public var details: String?
    /// The optional group title.
    public var group: String?
    /// Additional search terms.
    public var keywords: [String]
    /// The optional keyboard shortcut.
    public var shortcut: KeyboardShortcut?
    /// A Boolean value that indicates whether the command can run.
    public var isEnabled: Bool
    /// The action invoked for the command.
    public var action: @MainActor @Sendable () -> Void

    /// Creates a palette command.
    public init(
        id: ID,
        title: String,
        action: @escaping @MainActor @Sendable () -> Void,
        details: String? = nil,
        group: String? = nil,
        keywords: [String] = [],
        shortcut: KeyboardShortcut? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.group = group
        self.keywords = keywords
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// A searchable command collection backed by a select list.
@MainActor
public final class CommandPalette<ID: Hashable & Sendable> {
    /// The commands available in the palette.
    public var commands: [PaletteCommand<ID>] {
        didSet { synchronizeList() }
    }
    /// The select list that manages filtering and selection.
    public let selectList: SelectList<ID>

    /// Creates a command palette.
    /// - Complexity: O(*n*), where *n* is the number of commands.
    public init(commands: [PaletteCommand<ID>], id: SemanticID = "command-palette") {
        self.commands = commands
        selectList = SelectList(items: Self.items(from: commands), id: id)
        selectList.onActivate = { [weak self] id in
            self?.dispatch(id)
        }
    }

    /// The current search query.
    public var query: String {
        get { selectList.query }
        set { selectList.setQuery(newValue) }
    }

    /// Runs the enabled command with the specified identifier.
    /// - Complexity: O(*n*), where *n* is the number of commands.
    @discardableResult
    public func dispatch(_ id: ID) -> Bool {
        guard let command = commands.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        command.action()
        return true
    }

    /// Activates the selected command and returns its identifier.
    /// - Complexity: O(*n*), where *n* is the number of filtered commands.
    @discardableResult
    public func activateSelection() -> ID? {
        selectList.activateSelection()
    }

    private func synchronizeList() {
        selectList.items = Self.items(from: commands)
    }

    private static func items(from commands: [PaletteCommand<ID>]) -> [SelectListItem<ID>] {
        commands.map { command in
            var searchTerms = command.keywords
            if let shortcut = command.shortcut { searchTerms.append(shortcut.normalizedDescription) }
            return SelectListItem(
                id: command.id,
                title: command.title,
                details: command.details,
                group: command.group,
                searchTerms: searchTerms,
                isEnabled: command.isEnabled
            )
        }
    }
}
