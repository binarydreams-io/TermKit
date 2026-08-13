import TUIControls

public struct PaletteCommand<ID: Hashable & Sendable>: Sendable, Identifiable {
    public var id: ID
    public var title: String
    public var details: String?
    public var group: String?
    public var keywords: [String]
    public var shortcut: KeyboardShortcut?
    public var isEnabled: Bool
    public var action: @MainActor @Sendable () -> Void

    public init(
        id: ID,
        title: String,
        details: String? = nil,
        group: String? = nil,
        keywords: [String] = [],
        shortcut: KeyboardShortcut? = nil,
        isEnabled: Bool = true,
        action: @escaping @MainActor @Sendable () -> Void
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

@MainActor
public final class CommandPalette<ID: Hashable & Sendable> {
    public var commands: [PaletteCommand<ID>] {
        didSet { synchronizeList() }
    }
    public let selectList: SelectList<ID>

    public init(id: SemanticID = "command-palette", commands: [PaletteCommand<ID>]) {
        self.commands = commands
        selectList = SelectList(id: id, items: Self.items(from: commands))
        selectList.onActivate = { [weak self] id in
            self?.dispatch(id)
        }
    }

    public var query: String {
        get { selectList.query }
        set { selectList.setQuery(newValue) }
    }

    @discardableResult
    public func dispatch(_ id: ID) -> Bool {
        guard let command = commands.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        command.action()
        return true
    }

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
