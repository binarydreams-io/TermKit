/// The number of values a selection can contain.
public enum SelectionMode: Sendable, Hashable {
    /// At most one selected value.
    case single
    /// Any number of selected values.
    case multiple
}

/// A set of selected identifiers governed by a selection mode.
public struct Selection<ID: Hashable & Sendable>: Sendable, Hashable {
    /// The selection mode.
    public var mode: SelectionMode
    /// The selected identifiers.
    public private(set) var values: Set<ID>

    /// Creates a normalized selection.
    /// - Complexity: O(n) for single mode and O(1) for multiple mode.
    public init(mode: SelectionMode = .single, values: Set<ID> = []) {
        self.mode = mode
        self.values = mode == .single ? Set(values.prefix(1)) : values
    }

    /// An arbitrary selected identifier, if one exists.
    public var first: ID? { values.first }

    /// Returns whether an identifier is selected.
    /// - Complexity: O(1) on average.
    public func contains(_ id: ID) -> Bool {
        values.contains(id)
    }

    /// Selects an identifier according to the current mode.
    /// - Complexity: O(1) on average.
    public mutating func select(_ id: ID) {
        switch mode {
        case .single:
            values = [id]
        case .multiple:
            values.insert(id)
        }
    }

    /// Toggles an identifier's selected state.
    /// - Complexity: O(1) on average.
    public mutating func toggle(_ id: ID) {
        if values.remove(id) == nil { select(id) }
    }

    /// Removes an identifier from the selection.
    /// - Complexity: O(1) on average.
    public mutating func remove(_ id: ID) {
        values.remove(id)
    }

    /// Removes all selected identifiers.
    /// - Complexity: O(n), where n is the selection count.
    public mutating func clear() {
        values.removeAll()
    }
}

/// A selectable list item and its semantic metadata.
public struct ListItem<ID: Hashable & Sendable>: Sendable, Hashable, Identifiable {
    /// The item identifier.
    public var id: ID
    /// The item label.
    public var label: String
    /// The optional item value.
    public var value: String?
    /// A value that indicates whether the item can be selected.
    public var isEnabled: Bool

    /// Creates a list item.
    public init(id: ID, label: String, value: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.label = label
        self.value = value
        self.isEnabled = isEnabled
    }
}

/// A selectable list with keyboard and pointer navigation.
@MainActor
public final class List<ID: Hashable & Sendable> {
    /// The semantic identifier.
    public let id: SemanticID
    /// The displayed items.
    public var items: [ListItem<ID>] {
        didSet { normalizeState() }
    }
    /// The selected item identifiers.
    public var selection: Selection<ID> {
        didSet { normalizeState() }
    }
    /// The current navigation item identifier.
    public private(set) var currentID: ID?
    /// The action invoked when an item is activated.
    public var onActivate: (@MainActor @Sendable (_ id: ID) -> Void)?

    /// Creates a selectable list.
    /// - Complexity: O(n), where n is the item count.
    public init(
        items: [ListItem<ID>],
        id: SemanticID = "list",
        selection: Selection<ID> = Selection(),
        currentID: ID? = nil,
        onActivate: (@MainActor @Sendable (_ id: ID) -> Void)? = nil
    ) {
        self.id = id
        self.items = items
        self.selection = selection
        self.currentID = currentID
        self.onActivate = onActivate
        normalizeState()
    }

    /// Moves the current item by an offset.
    /// - Complexity: O(n), where n is the item count.
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

    /// Selects the current enabled item.
    /// - Complexity: O(n), where n is the item count.
    @discardableResult
    public func selectCurrent() -> ID? {
        guard let currentID, item(withID: currentID)?.isEnabled == true else { return nil }
        selection.select(currentID)
        return currentID
    }

    /// Selects and activates the current enabled item.
    /// - Complexity: O(n), where n is the item count.
    @discardableResult
    public func activateCurrent() -> ID? {
        guard let id = selectCurrent() else { return nil }
        onActivate?(id)
        return id
    }

    /// Selects the enabled item under a pointer location.
    /// - Complexity: O(n), where n is the item count.
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

    /// Creates the list's semantic node and item children.
    /// - Complexity: O(n), where n is the item count.
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
