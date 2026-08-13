import TUIControls
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public struct SelectListItem<ID: Hashable & Sendable>: Sendable, Hashable, Identifiable {
    public var id: ID
    public var title: String
    public var details: String?
    public var group: String?
    public var searchTerms: [String]
    public var isEnabled: Bool
    public var isCurrentValue: Bool

    public init(
        id: ID,
        title: String,
        details: String? = nil,
        group: String? = nil,
        searchTerms: [String] = [],
        isEnabled: Bool = true,
        isCurrentValue: Bool = false
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.group = group
        self.searchTerms = searchTerms
        self.isEnabled = isEnabled
        self.isCurrentValue = isCurrentValue
    }
}

public struct SelectListGroup<ID: Hashable & Sendable>: Sendable, Hashable {
    public var title: String?
    public var items: [SelectListItem<ID>]

    public init(title: String?, items: [SelectListItem<ID>]) {
        self.title = title
        self.items = items
    }
}

public struct SelectListFooterAction: Sendable, Hashable {
    public var title: String
    public var shortcut: KeyboardShortcut?
    public var action: @MainActor @Sendable () -> Void

    public init(
        title: String,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.shortcut == rhs.shortcut
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(shortcut)
    }
}

private enum SelectListDisplayRow<ID: Hashable & Sendable> {
    case group(String)
    case item(SelectListItem<ID>, isDetail: Bool)
}

@MainActor
public final class SelectList<ID: Hashable & Sendable> {
    public let id: SemanticID
    public var items: [SelectListItem<ID>] {
        didSet { normalizeSelection() }
    }
    public var query: String {
        didSet { normalizeSelection() }
    }
    public var footerActions: [SelectListFooterAction]
    public private(set) var selectedID: ID?
    public var onActivate: (@MainActor @Sendable (ID) -> Void)?
    fileprivate var renderedViewportHeight: Int?

    public init(
        id: SemanticID = "select-list",
        items: [SelectListItem<ID>],
        query: String = "",
        selectedID: ID? = nil,
        footerActions: [SelectListFooterAction] = [],
        onActivate: (@MainActor @Sendable (ID) -> Void)? = nil
    ) {
        self.id = id
        self.items = items
        self.query = query
        self.selectedID = selectedID
        self.footerActions = footerActions
        self.onActivate = onActivate
        normalizeSelection()
    }

    public var filteredItems: [SelectListItem<ID>] {
        let tokens = Self.normalizedTokens(query)
        guard tokens.isEmpty == false else { return items }
        return items.filter { item in
            let haystack = Self.normalize(
                ([item.title, item.details, item.group].compactMap { $0 } + item.searchTerms).joined(separator: " ")
            )
            return tokens.allSatisfy(haystack.contains)
        }
    }

    public var groups: [SelectListGroup<ID>] {
        var order: [String?] = []
        var grouped: [String?: [SelectListItem<ID>]] = [:]
        for item in filteredItems {
            if grouped[item.group] == nil { order.append(item.group) }
            grouped[item.group, default: []].append(item)
        }
        return order.map { SelectListGroup(title: $0, items: grouped[$0, default: []]) }
    }

    public func setQuery(_ query: String) {
        self.query = query
    }

    @discardableResult
    public func move(by delta: Int, wrapping: Bool = true) -> ID? {
        let enabled = filteredItems.filter(\.isEnabled)
        guard enabled.isEmpty == false else {
            selectedID = nil
            return nil
        }
        let current = selectedID.flatMap { id in enabled.firstIndex { $0.id == id } }
        var target = (current ?? (delta >= 0 ? -1 : enabled.count)) + delta
        if wrapping {
            target = (target % enabled.count + enabled.count) % enabled.count
        } else {
            target = min(max(0, target), enabled.count - 1)
        }
        selectedID = enabled[target].id
        return selectedID
    }

    @discardableResult
    public func select(at index: Int) -> ID? {
        guard filteredItems.indices.contains(index), filteredItems[index].isEnabled else { return nil }
        selectedID = filteredItems[index].id
        return selectedID
    }

    @discardableResult
    public func handleMouse(at point: CellPoint, rowFrames: [ID: CellRect], activate: Bool = false) -> ID? {
        guard let item = filteredItems.first(where: { $0.isEnabled && rowFrames[$0.id]?.contains(point) == true }) else {
            return nil
        }
        selectedID = item.id
        if activate { onActivate?(item.id) }
        return item.id
    }

    @discardableResult
    public func activateSelection() -> ID? {
        guard let selectedID, filteredItems.contains(where: { $0.id == selectedID && $0.isEnabled }) else { return nil }
        onActivate?(selectedID)
        return selectedID
    }

    @discardableResult
    public func activateFooterAction(matching shortcut: KeyboardShortcut) -> Bool {
        guard let action = footerActions.last(where: { $0.shortcut == shortcut }) else { return false }
        action.action()
        return true
    }

    @discardableResult
    public func activateFooterAction(at index: Int) -> Bool {
        guard footerActions.indices.contains(index) else { return false }
        footerActions[index].action()
        return true
    }

    public func view(rowHeight: Int = 1) -> SelectListView<ID> {
        SelectListView(list: self, rowHeight: rowHeight)
    }

    public func scrollOffset(rowHeight: Int = 1, viewportHeight: Int, currentOffset: Int) -> Int {
        let rows = displayRows(rowHeight: rowHeight)
        let boundedViewportHeight = max(0, viewportHeight)
        let maximumOffset = max(0, rows.count - boundedViewportHeight)
        let boundedOffset = min(max(0, currentOffset), maximumOffset)
        guard boundedViewportHeight > 0, let selectedID else { return boundedOffset }
        let selectedRows = rows.indices.filter {
            guard case .item(let item, _) = rows[$0] else { return false }
            return item.id == selectedID
        }
        guard let start = selectedRows.first, let last = selectedRows.last else { return boundedOffset }
        let end = last + 1
        if start < boundedOffset { return start }
        if end > boundedOffset + boundedViewportHeight { return min(maximumOffset, end - boundedViewportHeight) }
        return boundedOffset
    }

    public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
        let children = filteredItems.enumerated().map { index, item in
            var state: SemanticState = []
            if item.id == selectedID { state.insert(.selected) }
            if item.isCurrentValue { state.insert(.current) }
            if item.isEnabled == false { state.insert(.disabled) }
            return SemanticNode(
                id: SemanticID(rawValue: "\(id.rawValue)-item-\(index)"),
                role: .menuItem,
                label: item.title,
                value: item.details,
                state: state,
                actions: item.isEnabled ? [.activate, .focus] : []
            )
        }
        return SemanticNode(id: id, role: .menu, label: "Select list", value: query, frame: frame, children: children)
    }

    private func normalizeSelection() {
        let enabled = filteredItems.filter(\.isEnabled)
        if let selectedID, enabled.contains(where: { $0.id == selectedID }) { return }
        selectedID = enabled.first(where: \.isCurrentValue)?.id ?? enabled.first?.id
    }

    private static func normalizedTokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    fileprivate func displayRows(rowHeight: Int) -> [SelectListDisplayRow<ID>] {
        var rows: [SelectListDisplayRow<ID>] = []
        for group in groups {
            if let title = group.title { rows.append(.group(title)) }
            for item in group.items {
                rows.append(.item(item, isDetail: false))
                if item.details != nil { rows.append(.item(item, isDetail: true)) }
                let contentHeight = item.details == nil ? 1 : 2
                if rowHeight > contentHeight {
                    rows.append(contentsOf: repeatElement(.item(item, isDetail: true), count: rowHeight - contentHeight))
                }
            }
        }
        return rows
    }
}

public struct SelectListView<ID: Hashable & Sendable>: View, SemanticRenderable,
    ControlInputHandler, ControlShortcutHandler, ControlPointerActivatable {
    public let list: SelectList<ID>
    public let rowHeight: Int

    public init(list: SelectList<ID>, rowHeight: Int = 1) {
        precondition(rowHeight > 0, "A select-list row height must be positive.")
        self.list = list
        self.rowHeight = rowHeight
    }

    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(
            type: Self.self,
            primitive: self,
            focus: FocusMetadata(isFocusable: true),
            hitTest: HitTestMetadata(isEnabled: true),
            dirtyOnUpdate: .layout
        )]
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        MainActor.assumeIsolated {
            let rows = list.displayRows(rowHeight: rowHeight).count + (list.footerActions.isEmpty ? 0 : 1)
            let itemWidths = list.filteredItems.map { item in
                max(TerminalWidth.width(of: item.title), item.details.map(TerminalWidth.width(of:)) ?? 0) + 2
            }
            let groupWidths = list.groups.compactMap(\.title).map(TerminalWidth.width(of:))
            let footerWidth = list.footerActions.map(Self.footerText).joined(separator: "  ")
            let naturalWidth = (itemWidths + groupWidths + [TerminalWidth.width(of: footerWidth)]).max() ?? 0
            return CellSize(
                width: min(naturalWidth, proposal.width ?? naturalWidth),
                height: min(rows, proposal.height ?? rows)
            )
        }
    }

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        try MainActor.assumeIsolated {
            let rows = list.displayRows(rowHeight: rowHeight)
            let footerHeight = list.footerActions.isEmpty ? 0 : 1
            let viewportHeight = max(0, context.clip.height - footerHeight)
            list.renderedViewportHeight = viewportHeight
            let offset = list.scrollOffset(rowHeight: rowHeight, viewportHeight: viewportHeight, currentOffset: 0)
            for (visibleY, row) in rows.dropFirst(offset).prefix(viewportHeight).enumerated() {
                let rowContext = PaintContext(
                    origin: context.origin.offsetBy(dy: visibleY),
                    clip: context.clip
                )
                switch row {
                case .group(let title):
                    _ = try Text(title, style: CellStyle(attributes: [.bold, .dim]))
                        .paint(into: &surface, context: rowContext, resources: &resources)
                case .item(let item, let isDetail):
                    let selected = item.id == list.selectedID
                    var attributes: TextAttributes = []
                    if selected { attributes.insert(.inverse) }
                    if item.isCurrentValue { attributes.insert(.bold) }
                    if item.isEnabled == false || isDetail { attributes.insert(.dim) }
                    let text: String
                    if isDetail {
                        text = item.details.map { "  \($0)" } ?? ""
                    } else {
                        text = (item.isCurrentValue ? "▌ " : "  ") + item.title
                    }
                    _ = try Text(text, style: CellStyle(attributes: attributes))
                        .paint(into: &surface, context: rowContext, resources: &resources)
                }
            }
            if footerHeight > 0 {
                let footer = list.footerActions.map(Self.footerText).joined(separator: "  ")
                _ = try Text(footer, style: CellStyle(attributes: .dim)).paint(
                    into: &surface,
                    context: PaintContext(origin: context.origin.offsetBy(dy: viewportHeight), clip: context.clip),
                    resources: &resources
                )
            }
            return list.semanticNode(frame: context.clip)
        }
    }

    public func handleControlInput(_ event: ControlInputEvent) -> Bool {
        switch event {
        case .moveUp: list.move(by: -1); return true
        case .moveDown: list.move(by: 1); return true
        case .submit: return list.activateSelection() != nil
        default: return false
        }
    }

    public func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        list.activateFooterAction(matching: shortcut)
    }

    public func activate(at point: CellPoint) -> Bool {
        let footerHeight = list.footerActions.isEmpty ? 0 : 1
        let viewportHeight = list.renderedViewportHeight ?? list.displayRows(rowHeight: rowHeight).count
        if footerHeight > 0, point.y == viewportHeight {
            var x = 0
            for (index, action) in list.footerActions.enumerated() {
                let width = TerminalWidth.width(of: Self.footerText(action))
                if point.x >= x, point.x < x + width { return list.activateFooterAction(at: index) }
                x += width + 2
            }
            return false
        }
        guard point.y >= 0, point.y < viewportHeight else { return false }
        let rows = list.displayRows(rowHeight: rowHeight)
        let offset = list.scrollOffset(rowHeight: rowHeight, viewportHeight: viewportHeight, currentOffset: 0)
        guard rows.indices.contains(offset + point.y) else { return false }
        var frames: [ID: CellRect] = [:]
        for (visibleY, row) in rows.dropFirst(offset).prefix(viewportHeight).enumerated() {
            guard case .item(let item, _) = row else { continue }
            let frame = CellRect(x: 0, y: visibleY, width: Int.max, height: 1)
            if let existing = frames[item.id] {
                frames[item.id] = existing.union(frame)
            } else {
                frames[item.id] = frame
            }
        }
        return list.handleMouse(at: point, rowFrames: frames, activate: true) != nil
    }

    nonisolated private static func footerText(_ action: SelectListFooterAction) -> String {
        action.shortcut.map { "\(action.title) [\($0.normalizedDescription)]" } ?? action.title
    }
}
