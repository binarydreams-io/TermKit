import TUIFoundation

public enum SelectionMode: Sendable, Hashable {
    case single
    case multiple
}

public struct Selection<ID: Hashable & Sendable>: Sendable, Hashable {
    public var mode: SelectionMode
    public private(set) var values: Set<ID>

    public init(mode: SelectionMode = .single, values: Set<ID> = []) {
        self.mode = mode
        self.values = mode == .single ? Set(values.prefix(1)) : values
    }

    public var first: ID? { values.first }

    public func contains(_ id: ID) -> Bool {
        values.contains(id)
    }

    public mutating func select(_ id: ID) {
        switch mode {
        case .single:
            values = [id]
        case .multiple:
            values.insert(id)
        }
    }

    public mutating func toggle(_ id: ID) {
        if values.remove(id) == nil { select(id) }
    }

    public mutating func remove(_ id: ID) {
        values.remove(id)
    }

    public mutating func clear() {
        values.removeAll()
    }
}

public struct ListItem<ID: Hashable & Sendable>: Sendable, Hashable, Identifiable {
    public var id: ID
    public var label: String
    public var value: String?
    public var isEnabled: Bool

    public init(id: ID, label: String, value: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.label = label
        self.value = value
        self.isEnabled = isEnabled
    }
}

@MainActor
public final class List<ID: Hashable & Sendable> {
    public let id: SemanticID
    public var items: [ListItem<ID>] {
        didSet { normalizeState() }
    }
    public var selection: Selection<ID> {
        didSet { normalizeState() }
    }
    public private(set) var currentID: ID?
    public var onActivate: (@MainActor @Sendable (ID) -> Void)?

    public init(
        id: SemanticID = "list",
        items: [ListItem<ID>],
        selection: Selection<ID> = Selection(),
        currentID: ID? = nil,
        onActivate: (@MainActor @Sendable (ID) -> Void)? = nil
    ) {
        self.id = id
        self.items = items
        self.selection = selection
        self.currentID = currentID
        self.onActivate = onActivate
        normalizeState()
    }

    @discardableResult
    public func move(by delta: Int, wrapping: Bool = false) -> ID? {
        let enabled = items.filter(\.isEnabled)
        guard enabled.isEmpty == false else {
            currentID = nil
            return nil
        }

        let currentIndex = currentID.flatMap { id in enabled.firstIndex { $0.id == id } }
        var target = (currentIndex ?? (delta >= 0 ? -1 : enabled.count)) + delta
        if wrapping {
            target = (target % enabled.count + enabled.count) % enabled.count
        } else {
            target = min(max(0, target), enabled.count - 1)
        }
        currentID = enabled[target].id
        return currentID
    }

    @discardableResult
    public func selectCurrent() -> ID? {
        guard let currentID, item(withID: currentID)?.isEnabled == true else { return nil }
        selection.select(currentID)
        return currentID
    }

    @discardableResult
    public func activateCurrent() -> ID? {
        guard let id = selectCurrent() else { return nil }
        onActivate?(id)
        return id
    }

    @discardableResult
    public func handleMouse(at point: CellPoint, rowFrames: [ID: CellRect], activate: Bool = false) -> ID? {
        guard let item = items.first(where: { rowFrames[$0.id]?.contains(point) == true && $0.isEnabled }) else {
            return nil
        }
        currentID = item.id
        selection.select(item.id)
        if activate { onActivate?(item.id) }
        return item.id
    }

    public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
        let children = items.enumerated().map { index, item in
            var state: SemanticState = []
            if selection.contains(item.id) { state.insert(.selected) }
            if currentID == item.id { state.insert(.current) }
            if item.isEnabled == false { state.insert(.disabled) }
            return SemanticNode(
                id: SemanticID(rawValue: "\(id.rawValue)-item-\(index)"),
                role: .listItem,
                label: item.label,
                value: item.value,
                state: state,
                actions: item.isEnabled ? [.activate, .focus] : []
            )
        }
        return SemanticNode(id: id, role: .list, label: "List", frame: frame, children: children)
    }

    private func item(withID id: ID) -> ListItem<ID>? {
        items.first { $0.id == id }
    }

    private func normalizeState() {
        let validIDs = Set(items.map(\.id))
        for selectedID in selection.values where validIDs.contains(selectedID) == false {
            selection.remove(selectedID)
        }
        if let currentID, item(withID: currentID)?.isEnabled != true {
            self.currentID = items.first(where: \.isEnabled)?.id
        } else if currentID == nil {
            currentID = items.first(where: \.isEnabled)?.id
        }
    }
}
