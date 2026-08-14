/// A searchable item in a select list.
public struct SelectListItem<ID: Hashable & Sendable>: Sendable, Hashable, Identifiable {
  /// The stable item identifier.
  public var id: ID
  /// The primary item title.
  public var title: String
  /// Optional detail text.
  public var details: String?
  /// The optional group title.
  public var group: String?
  /// Additional terms used during filtering.
  public var searchTerms: [String]
  /// A Boolean value that indicates whether the item can be selected.
  public var isEnabled: Bool
  /// A Boolean value that indicates the current external value.
  public var isCurrentValue: Bool

  /// Creates a select-list item.
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

/// An ordered group of select-list items.
public struct SelectListGroup<ID: Hashable & Sendable>: Sendable, Hashable {
  /// The optional group title.
  public var title: String?
  /// The items in the group.
  public var items: [SelectListItem<ID>]

  /// Creates a select-list group.
  public init(title: String?, items: [SelectListItem<ID>]) {
    self.title = title
    self.items = items
  }
}

/// An action displayed in a select-list footer.
public struct SelectListFooterAction: Sendable, Hashable {
  /// The action title.
  public var title: String
  /// The optional keyboard shortcut.
  public var shortcut: KeyboardShortcut?
  /// The action to invoke.
  public var action: @MainActor @Sendable () -> Void

  /// Creates a footer action.
  public init(
    title: String,
    shortcut: KeyboardShortcut? = nil,
    action: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.title = title
    self.shortcut = shortcut
    self.action = action
  }

  /// Returns whether two footer actions have the same title and shortcut.
  /// - Complexity: O(*n*), where *n* is the title length.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.title == rhs.title && lhs.shortcut == rhs.shortcut
  }

  /// Hashes the title and shortcut.
  /// - Complexity: O(*n*), where *n* is the title length.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(title)
    hasher.combine(shortcut)
  }
}

private enum SelectListDisplayRow<ID: Hashable & Sendable> {
  case group(String)
  case item(SelectListItem<ID>, isDetail: Bool)
}

/// The values available to custom select-list row content.
public struct SelectListRowConfiguration<ID: Hashable & Sendable>: Sendable, Hashable {
  /// The item for the row.
  public let item: SelectListItem<ID>
  /// A Boolean value that indicates whether the row is selected.
  public let isSelected: Bool

  /// Creates a row configuration.
  public init(item: SelectListItem<ID>, isSelected: Bool) {
    self.item = item
    self.isSelected = isSelected
  }
}

private struct SelectListContentLayoutEntry<ID: Hashable & Sendable> {
  enum Content {
    case group(String)
    case item(SelectListItem<ID>, any SemanticRenderable)
  }

  var content: Content
  var y: Int
  var height: Int
}

/// A searchable, grouped selection model.
@MainActor
public final class SelectList<ID: Hashable & Sendable> {
  /// The semantic identifier.
  public let id: SemanticID
  /// The available items.
  public var items: [SelectListItem<ID>] {
    didSet { normalizeSelection() }
  }

  /// The current search query.
  public var query: String {
    didSet { normalizeSelection() }
  }

  /// The actions displayed in the footer.
  public var footerActions: [SelectListFooterAction]
  /// The selected item identifier.
  public private(set) var selectedID: ID?
  /// The action invoked when an item activates.
  public var onActivate: (@MainActor @Sendable (_ id: ID) -> Void)?
  fileprivate var renderedViewportHeight: Int?
  fileprivate var renderedViewportWidth: Int?

  /// Creates a select list and normalizes its initial selection.
  /// - Complexity: O(*n*), where *n* is the number of items.
  public init(
    items: [SelectListItem<ID>],
    id: SemanticID = "select-list",
    query: String = "",
    selectedID: ID? = nil,
    footerActions: [SelectListFooterAction] = [],
    onActivate: (@MainActor @Sendable (_ id: ID) -> Void)? = nil
  ) {
    self.id = id
    self.items = items
    self.query = query
    self.selectedID = selectedID
    self.footerActions = footerActions
    self.onActivate = onActivate
    normalizeSelection()
  }

  /// The items that contain every normalized query token.
  /// - Complexity: O(*n* × *m*), where *n* is item count and *m* is searchable text length.
  public var filteredItems: [SelectListItem<ID>] {
    let tokens = Self.normalizedTokens(query)
    guard tokens.isEmpty == false else { return items }
    return items.filter { item in
      let haystack = Self.normalize(
        ([item.title, item.details, item.group].compactMap(\.self) + item.searchTerms).joined(separator: " ")
      )
      return tokens.allSatisfy(haystack.contains)
    }
  }

  /// The filtered items grouped in first-occurrence order.
  /// - Complexity: O(*n*), where *n* is the number of filtered items.
  public var groups: [SelectListGroup<ID>] {
    var order: [String?] = []
    var grouped: [String?: [SelectListItem<ID>]] = [:]
    for item in filteredItems {
      if grouped[item.group] == nil {
        order.append(item.group)
      }
      grouped[item.group, default: []].append(item)
    }
    return order.map { SelectListGroup(title: $0, items: grouped[$0, default: []]) }
  }

  /// Sets the search query and normalizes the selection.
  /// - Complexity: O(*n* × *m*), where *n* is item count and *m* is searchable text length.
  public func setQuery(_ query: String) {
    self.query = query
  }

  /// Moves the selection among enabled filtered items.
  /// - Complexity: O(*n*), where *n* is the number of items.
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

  /// Selects an enabled filtered item at an index.
  /// - Complexity: O(*n*), where *n* is the number of items.
  @discardableResult
  public func select(at index: Int) -> ID? {
    guard filteredItems.indices.contains(index), filteredItems[index].isEnabled else { return nil }
    selectedID = filteredItems[index].id
    return selectedID
  }

  /// Selects the enabled item whose row contains a pointer location.
  /// - Complexity: O(*n*), where *n* is the number of filtered items.
  @discardableResult
  public func handleMouse(at point: CellPoint, rowFrames: [ID: CellRect], activate: Bool = false) -> ID? {
    guard let item = filteredItems.first(where: { $0.isEnabled && rowFrames[$0.id]?.contains(point) == true }) else {
      return nil
    }
    selectedID = item.id
    if activate {
      onActivate?(item.id)
    }
    return item.id
  }

  /// Activates the selected enabled item.
  /// - Complexity: O(*n*), where *n* is the number of filtered items.
  @discardableResult
  public func activateSelection() -> ID? {
    guard let selectedID, filteredItems.contains(where: { $0.id == selectedID && $0.isEnabled }) else { return nil }
    onActivate?(selectedID)
    return selectedID
  }

  /// Activates the last footer action that matches a shortcut.
  /// - Complexity: O(*n*), where *n* is the number of footer actions.
  @discardableResult
  public func activateFooterAction(matching shortcut: KeyboardShortcut) -> Bool {
    guard let action = footerActions.last(where: { $0.shortcut == shortcut }) else { return false }
    action.action()
    return true
  }

  /// Activates the footer action at an index.
  /// - Complexity: O(1).
  @discardableResult
  public func activateFooterAction(at index: Int) -> Bool {
    guard footerActions.indices.contains(index) else { return false }
    footerActions[index].action()
    return true
  }

  /// Creates a view for the list.
  /// - Complexity: O(1).
  public func view(rowHeight: Int = 1) -> SelectListView<ID> {
    SelectListView(list: self, rowHeight: rowHeight)
  }

  /// Creates a view that uses custom content for each item row.
  /// - Complexity: O(1).
  public func view(
    rowHeight: Int = 1,
    rowContent: @escaping @MainActor @Sendable (_ configuration: SelectListRowConfiguration<ID>) -> some SemanticRenderable
  ) -> SelectListView<ID> {
    SelectListView(list: self, rowHeight: rowHeight, rowContent: rowContent)
  }

  /// Returns an offset that keeps the selection visible in a viewport.
  /// - Complexity: O(*n*), where *n* is the number of display rows.
  public func scrollOffset(viewportHeight: Int, currentOffset: Int, rowHeight: Int = 1) -> Int {
    let rows = displayRows(rowHeight: rowHeight)
    let boundedViewportHeight = max(0, viewportHeight)
    let maximumOffset = max(0, rows.count - boundedViewportHeight)
    let boundedOffset = min(max(0, currentOffset), maximumOffset)
    guard boundedViewportHeight > 0, let selectedID else { return boundedOffset }
    let selectedRows = rows.indices.filter {
      guard case let .item(item, _) = rows[$0] else { return false }
      return item.id == selectedID
    }
    guard let start = selectedRows.first, let last = selectedRows.last else { return boundedOffset }
    let end = last + 1
    if start < boundedOffset {
      return start
    }
    if end > boundedOffset + boundedViewportHeight {
      return min(maximumOffset, end - boundedViewportHeight)
    }
    return boundedOffset
  }

  /// Creates the semantic menu tree for the filtered items.
  /// - Complexity: O(*n*), where *n* is the number of filtered items.
  public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
    let children = filteredItems.enumerated().map { index, item in
      var state: SemanticState = []
      if item.id == selectedID {
        state.insert(.selected)
      }
      if item.isCurrentValue {
        state.insert(.current)
      }
      if item.isEnabled == false {
        state.insert(.disabled)
      }
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
    if let selectedID, enabled.contains(where: { $0.id == selectedID }) {
      return
    }
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
      if let title = group.title {
        rows.append(.group(title))
      }
      for item in group.items {
        rows.append(.item(item, isDetail: false))
        if item.details != nil {
          rows.append(.item(item, isDetail: true))
        }
        let contentHeight = item.details == nil ? 1 : 2
        if rowHeight > contentHeight {
          rows.append(contentsOf: repeatElement(.item(item, isDetail: true), count: rowHeight - contentHeight))
        }
      }
    }
    return rows
  }
}

/// An interactive terminal view for a select list.
public struct SelectListView<ID: Hashable & Sendable>: View, SemanticRenderable,
  ControlInputHandler, ControlShortcutHandler, ControlPointerActivatable
{
  /// The select-list model.
  public let list: SelectList<ID>
  /// The minimum visual height of each item.
  public let rowHeight: Int
  private let rowContent: (@MainActor @Sendable (SelectListRowConfiguration<ID>) -> any SemanticRenderable)?

  /// Creates a select-list view.
  public init(list: SelectList<ID>, rowHeight: Int = 1) {
    precondition(rowHeight > 0, "A select-list row height must be positive.")
    self.list = list
    self.rowHeight = rowHeight
    self.rowContent = nil
  }

  /// Creates a select-list view that uses custom content for each item row.
  public init(
    list: SelectList<ID>,
    rowHeight: Int = 1,
    rowContent: @escaping @MainActor @Sendable (_ configuration: SelectListRowConfiguration<ID>) -> some SemanticRenderable
  ) {
    precondition(rowHeight > 0, "A select-list row height must be positive.")
    self.list = list
    self.rowHeight = rowHeight
    self.rowContent = { configuration in rowContent(configuration) }
  }

  /// The focusable primitive node descriptor.
  public var graphBody: [NodeDescriptor] {
    [
      NodeDescriptor(
        type: Self.self,
        primitive: self,
        focus: FocusMetadata(id: FocusID(rawValue: list.id.rawValue), isFocusable: true),
        hitTest: HitTestMetadata(isEnabled: true),
        dirtyOnUpdate: .layout
      )
    ]
  }

  /// Returns the list size constrained by a proposal.
  /// - Complexity: O(*n*), where *n* is the number of filtered items.
  public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    if rowContent != nil {
      let entries = contentLayout(width: proposal.width)
      let naturalWidth = entries.map { entry in
        switch entry.content {
        case let .group(title): TerminalWidth.width(of: title)
        case let .item(_, content): content.sizeThatFits(.unspecified).width
        }
      }.max() ?? 0
      let footerWidth = list.footerActions.map(Self.footerText).joined(separator: "  ")
      let width = min(max(naturalWidth, TerminalWidth.width(of: footerWidth)), proposal.width ?? .max)
      let rows = entries.last.map { $0.y + $0.height } ?? 0
      let height = rows + (list.footerActions.isEmpty ? 0 : 1)
      return CellSize(width: width, height: min(height, proposal.height ?? height))
    }
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

  /// Paints visible rows and returns the list's semantic node.
  /// - Complexity: O(*n*), where *n* is the number of display rows.
  public func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    if rowContent != nil {
      return try paintContent(into: &surface, context: context, resources: &resources)
    }
    let rows = list.displayRows(rowHeight: rowHeight)
    let footerHeight = list.footerActions.isEmpty ? 0 : 1
    let viewportHeight = max(0, context.clip.height - footerHeight)
    list.renderedViewportHeight = viewportHeight
    let offset = list.scrollOffset(viewportHeight: viewportHeight, currentOffset: 0, rowHeight: rowHeight)
    for (visibleY, row) in rows.dropFirst(offset).prefix(viewportHeight).enumerated() {
      let rowContext = PaintContext(
        clip: context.clip,
        origin: context.origin.offsetBy(dy: visibleY)
      )
      switch row {
      case let .group(title):
        _ = try Text(title, style: CellStyle(attributes: [.bold, .dim]))
          .paint(into: &surface, context: rowContext, resources: &resources)
      case let .item(item, isDetail):
        let selected = item.id == list.selectedID
        var attributes: TextAttributes = []
        if selected {
          attributes.insert(.inverse)
        }
        if item.isCurrentValue {
          attributes.insert(.bold)
        }
        if item.isEnabled == false || isDetail {
          attributes.insert(.dim)
        }
        let text: String = if isDetail {
          item.details.map { "  \($0)" } ?? ""
        } else {
          (item.isCurrentValue ? "▌ " : "  ") + item.title
        }
        _ = try Text(text, style: CellStyle(attributes: attributes))
          .paint(into: &surface, context: rowContext, resources: &resources)
      }
    }
    if footerHeight > 0 {
      let footer = list.footerActions.map(Self.footerText).joined(separator: "  ")
      _ = try Text(footer, style: CellStyle(attributes: .dim)).paint(
        into: &surface,
        context: PaintContext(clip: context.clip, origin: context.origin.offsetBy(dy: viewportHeight)),
        resources: &resources
      )
    }
    return list.semanticNode(frame: context.clip)
  }

  /// Handles movement and submission control input.
  /// - Complexity: O(*n*), where *n* is the number of list items.
  public func handleControlInput(_ event: ControlInputEvent) -> Bool {
    switch event {
    case .moveUp:
      list.move(by: -1)
      return true
    case .moveDown:
      list.move(by: 1)
      return true
    case .submit: return list.activateSelection() != nil
    default: return false
    }
  }

  /// Handles a footer keyboard shortcut.
  /// - Complexity: O(*n*), where *n* is the number of footer actions.
  public func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool {
    list.activateFooterAction(matching: shortcut)
  }

  /// Activates the item or footer action at a pointer location.
  /// - Complexity: O(*n*), where *n* is the number of display rows.
  public func activate(at point: CellPoint) -> Bool {
    let footerHeight = list.footerActions.isEmpty ? 0 : 1
    let viewportHeight = list.renderedViewportHeight ?? list.displayRows(rowHeight: rowHeight).count
    if footerHeight > 0, point.y == viewportHeight {
      var x = 0
      for (index, action) in list.footerActions.enumerated() {
        let width = TerminalWidth.width(of: Self.footerText(action))
        if point.x >= x, point.x < x + width {
          return list.activateFooterAction(at: index)
        }
        x += width + 2
      }
      return false
    }
    guard point.y >= 0, point.y < viewportHeight else { return false }
    if rowContent != nil {
      let entries = contentLayout(width: list.renderedViewportWidth)
      let offset = contentScrollOffset(entries: entries, viewportHeight: viewportHeight, currentOffset: 0)
      var frames: [ID: CellRect] = [:]
      for entry in entries {
        guard case let .item(item, _) = entry.content else { continue }
        let visibleStart = max(entry.y, offset)
        let visibleEnd = min(entry.y + entry.height, offset + viewportHeight)
        guard visibleStart < visibleEnd else { continue }
        frames[item.id] = CellRect(
          x: 0,
          y: visibleStart - offset,
          width: Int.max,
          height: visibleEnd - visibleStart
        )
      }
      return list.handleMouse(at: point, rowFrames: frames, activate: true) != nil
    }
    let rows = list.displayRows(rowHeight: rowHeight)
    let offset = list.scrollOffset(viewportHeight: viewportHeight, currentOffset: 0, rowHeight: rowHeight)
    guard rows.indices.contains(offset + point.y) else { return false }
    var frames: [ID: CellRect] = [:]
    for (visibleY, row) in rows.dropFirst(offset).prefix(viewportHeight).enumerated() {
      guard case let .item(item, _) = row else { continue }
      let frame = CellRect(x: 0, y: visibleY, width: Int.max, height: 1)
      if let existing = frames[item.id] {
        frames[item.id] = existing.union(frame)
      } else {
        frames[item.id] = frame
      }
    }
    return list.handleMouse(at: point, rowFrames: frames, activate: true) != nil
  }

  private nonisolated static func footerText(_ action: SelectListFooterAction) -> String {
    action.shortcut.map { "\(action.title) [\($0.normalizedDescription)]" } ?? action.title
  }

  private func contentLayout(width: Int?) -> [SelectListContentLayoutEntry<ID>] {
    guard let rowContent else { return [] }
    var entries: [SelectListContentLayoutEntry<ID>] = []
    var y = 0
    for group in list.groups {
      if let title = group.title {
        entries.append(SelectListContentLayoutEntry(content: .group(title), y: y, height: 1))
        y += 1
      }
      for item in group.items {
        let content = rowContent(SelectListRowConfiguration(item: item, isSelected: item.id == list.selectedID))
        let contentHeight = content.sizeThatFits(ProposedCellSize(width: width)).height
        let height = max(rowHeight, contentHeight)
        entries.append(SelectListContentLayoutEntry(content: .item(item, content), y: y, height: height))
        y += height
      }
    }
    return entries
  }

  private func contentScrollOffset(
    entries: [SelectListContentLayoutEntry<ID>],
    viewportHeight: Int,
    currentOffset: Int
  ) -> Int {
    let contentHeight = entries.last.map { $0.y + $0.height } ?? 0
    let boundedViewportHeight = max(0, viewportHeight)
    let maximumOffset = max(0, contentHeight - boundedViewportHeight)
    let boundedOffset = min(max(0, currentOffset), maximumOffset)
    guard boundedViewportHeight > 0, let selectedID = list.selectedID,
          let selected = entries.first(where: {
            guard case let .item(item, _) = $0.content else { return false }
            return item.id == selectedID
          })
    else {
      return boundedOffset
    }
    if selected.y < boundedOffset {
      return selected.y
    }
    let end = selected.y + selected.height
    if end > boundedOffset + boundedViewportHeight {
      return min(maximumOffset, end - boundedViewportHeight)
    }
    return boundedOffset
  }

  private func paintContent(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let entries = contentLayout(width: context.clip.width)
    let footerHeight = list.footerActions.isEmpty ? 0 : 1
    let viewportHeight = max(0, context.clip.height - footerHeight)
    list.renderedViewportHeight = viewportHeight
    list.renderedViewportWidth = context.clip.width
    let offset = contentScrollOffset(entries: entries, viewportHeight: viewportHeight, currentOffset: 0)
    let viewportClip = CellRect(
      origin: context.clip.origin,
      size: CellSize(width: context.clip.width, height: viewportHeight)
    )
    for entry in entries where entry.y + entry.height > offset && entry.y < offset + viewportHeight {
      let rowContext = PaintContext(
        clip: viewportClip,
        origin: context.origin.offsetBy(dy: entry.y - offset)
      )
      switch entry.content {
      case let .group(title):
        _ = try Text(title, style: CellStyle(attributes: [.bold, .dim]))
          .paint(into: &surface, context: rowContext, resources: &resources)
      case let .item(_, content):
        _ = try content.paint(into: &surface, context: rowContext, resources: &resources)
      }
    }
    if footerHeight > 0 {
      let footer = list.footerActions.map(Self.footerText).joined(separator: "  ")
      _ = try Text(footer, style: CellStyle(attributes: .dim)).paint(
        into: &surface,
        context: PaintContext(clip: context.clip, origin: context.origin.offsetBy(dy: viewportHeight)),
        resources: &resources
      )
    }
    return list.semanticNode(frame: context.clip)
  }
}
