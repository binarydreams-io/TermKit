/// Actions emitted by a conversation viewport.
public struct ConversationViewportActions: Sendable {
  /// Reports a forward scroll.
  public var scrollForward: @MainActor @Sendable () -> Void
  /// Reports a backward scroll.
  public var scrollBackward: @MainActor @Sendable () -> Void

  /// Creates conversation viewport actions.
  public init(
    scrollForward: @escaping @MainActor @Sendable () -> Void = {},
    scrollBackward: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.scrollForward = scrollForward
    self.scrollBackward = scrollBackward
  }
}

/// A view that presents conversation items through a lazy viewport.
public struct ConversationViewportView<Item: AgentContentPresentable>: View {
  /// The conversation items.
  public var items: [Item]
  /// A binding to the viewport state.
  public var state: Binding<ConversationViewportState>
  /// The viewport actions.
  public var actions: ConversationViewportActions
  /// The resolved semantic theme.
  public var theme: ResolvedSemanticTheme

  /// Creates a conversation viewport view.
  public init(
    items: [Item],
    state: Binding<ConversationViewportState>,
    theme: ResolvedSemanticTheme,
    actions: ConversationViewportActions = ConversationViewportActions()
  ) {
    self.items = items
    self.state = state
    self.actions = actions
    self.theme = theme
  }

  /// The view graph for the conversation viewport.
  /// - Complexity: O(1), excluding child rendering.
  public var graphBody: [NodeDescriptor] {
    AgentComponentView(items: items, state: state, theme: theme, actions: actions).graphBody
  }
}

/// The lazy plan for a transcript. It contains indexes, not transcript items.
public struct ConversationVisiblePlan: Sendable, Hashable {
  /// The indexes of items to render.
  public var visibleRange: Range<Int>
  /// The total content extent in cells.
  public var contentExtent: Double

  /// Creates a visible conversation plan.
  public init(visibleRange: Range<Int>, contentExtent: Double) {
    self.visibleRange = visibleRange
    self.contentExtent = contentExtent
  }
}

/// A transcript anchor before and after older items are prepended.
public struct ConversationPrependAnchor: Sendable, Hashable {
  /// The visual anchor before items were prepended.
  public var previous: ScrollAnchor
  /// The corresponding anchor after items were prepended.
  public var resolved: ScrollAnchor

  /// Creates a prepend anchor pair.
  public init(previous: ScrollAnchor, resolved: ScrollAnchor) {
    self.previous = previous
    self.resolved = resolved
  }
}

/// A lazy transcript viewport with measured or estimated item extents.
public struct ConversationViewportState: Sendable, Hashable {
  /// The number of conversation items.
  public private(set) var itemCount: Int
  /// The current scroll state.
  public private(set) var scrollState: ScrollState
  /// The estimated extent of one item.
  public private(set) var itemExtent: Double
  /// The spacing between items.
  public private(set) var spacing: Double
  /// The number of extra items rendered outside the viewport.
  public private(set) var overscan: Int
  /// The measured item extents, if available.
  public private(set) var itemExtents: [Double]?
  /// A Boolean value that controls whether new output stays at the bottom.
  public var anchorsNewOutputToBottom: Bool

  /// Creates conversation viewport state.
  /// - Complexity: O(n) when measured item extents are supplied; otherwise O(1).
  public init(
    viewportExtent: Double,
    itemExtent: Double,
    itemCount: Int = 0,
    spacing: Double = 0,
    overscan: Int = 2,
    itemExtents: [Double]? = nil,
    initiallyPinnedToBottom: Bool = true
  ) {
    precondition(itemCount >= 0)
    precondition(itemExtent > 0 && itemExtent.isFinite)
    precondition(itemExtents == nil || itemExtents?.count == itemCount)
    precondition(itemExtents?.allSatisfy { $0 > 0 && $0.isFinite } != false)
    self.itemExtents = itemExtents
    let extent = Self.contentExtent(itemCount: itemCount, itemExtent: itemExtent, itemExtents: itemExtents, spacing: spacing)
    let offset = initiallyPinnedToBottom ? max(0, extent - viewportExtent) : 0
    self.itemCount = itemCount
    self.scrollState = ScrollState(viewportExtent: viewportExtent, contentExtent: extent, offset: offset)
    self.itemExtent = itemExtent
    self.spacing = spacing
    self.overscan = overscan
    self.anchorsNewOutputToBottom = true
  }

  /// A Boolean value that indicates whether the viewport is pinned to the bottom.
  /// - Complexity: O(1).
  public var isPinnedToBottom: Bool {
    scrollState.isPinnedToBottom()
  }

  /// Returns the item range to render for the current viewport.
  /// - Complexity: O(n log n) with measured extents; otherwise O(1).
  public func visiblePlan() -> ConversationVisiblePlan {
    if itemExtents != nil {
      let firstVisible = itemIndex(at: scrollState.offset)
      let lastVisible = itemIndex(at: max(scrollState.offset, scrollState.offset + scrollState.viewportExtent.nextDown))
      let lower = max(0, firstVisible - overscan)
      let upper = min(itemCount, max(lower, lastVisible + 1 + overscan))
      return ConversationVisiblePlan(visibleRange: lower ..< upper, contentExtent: contentExtent)
    }
    let plan = planner.plan(
      itemCount: itemCount,
      viewport: scrollState.offset ..< (scrollState.offset + scrollState.viewportExtent)
    )
    return ConversationVisiblePlan(visibleRange: plan.visibleRange, contentExtent: plan.contentExtent)
  }

  /// Returns the item and offset at the viewport start.
  /// - Complexity: O(n log n) with measured extents; otherwise O(1).
  public func visualAnchor() -> ScrollAnchor {
    guard itemCount > 0 else { return ScrollAnchor(itemIndex: 0, offsetFromViewportStart: 0) }
    let itemIndex = itemIndex(at: scrollState.offset)
    return ScrollAnchor(
      itemIndex: itemIndex,
      offsetFromViewportStart: origin(of: itemIndex) - scrollState.offset
    )
  }

  /// Scrolls to the specified content offset.
  /// - Complexity: O(1).
  public mutating func scroll(to offset: Double) {
    scrollState = ScrollState(
      viewportExtent: scrollState.viewportExtent,
      contentExtent: scrollState.contentExtent,
      offset: offset
    )
  }

  /// Updates the viewport extent while preserving bottom pinning.
  /// - Complexity: O(1).
  public mutating func updateViewportExtent(_ viewportExtent: Double) {
    let wasPinned = isPinnedToBottom
    scrollState = ScrollState(
      viewportExtent: viewportExtent,
      contentExtent: scrollState.contentExtent,
      offset: wasPinned ? max(0, scrollState.contentExtent - viewportExtent) : scrollState.offset
    )
  }

  /// Replaces estimated layout metrics and preserves the visual anchor.
  /// - Complexity: O(n), where n is the number of measured item extents.
  public mutating func updateMetrics(itemExtent: Double, spacing: Double, overscan: Int) {
    precondition(itemExtent > 0 && itemExtent.isFinite)
    precondition(spacing >= 0 && spacing.isFinite)
    precondition(overscan >= 0)
    let wasPinned = isPinnedToBottom
    let anchor = visualAnchor()
    self.itemExtent = itemExtent
    self.spacing = spacing
    self.overscan = overscan
    itemExtents = nil
    let newExtent = contentExtent
    scrollState = ScrollState(
      viewportExtent: scrollState.viewportExtent,
      contentExtent: newExtent,
      offset: wasPinned
        ? max(0, newExtent - scrollState.viewportExtent)
        : origin(of: anchor.itemIndex) - anchor.offsetFromViewportStart
    )
  }

  /// Replaces measured item extents and preserves the visual anchor.
  /// - Complexity: O(n), where n is the number of item extents.
  public mutating func updateItemExtents(_ extents: [Double]) {
    precondition(extents.count == itemCount)
    precondition(extents.allSatisfy { $0 > 0 && $0.isFinite })
    let wasPinned = isPinnedToBottom
    let anchor = visualAnchor()
    itemExtents = extents
    let newExtent = contentExtent
    scrollState = ScrollState(
      viewportExtent: scrollState.viewportExtent,
      contentExtent: newExtent,
      offset: wasPinned
        ? max(0, newExtent - scrollState.viewportExtent)
        : origin(of: anchor.itemIndex) - anchor.offsetFromViewportStart
    )
  }

  /// Prepends items and returns the anchor before and after the update.
  /// - Complexity: O(n + p), where n is the item count and p is the prepended count.
  @discardableResult
  public mutating func prepend(itemCount prependedCount: Int) -> ConversationPrependAnchor {
    precondition(prependedCount >= 0)
    let previous = visualAnchor()
    let previousOrigin = origin(of: previous.itemIndex)
    itemCount += prependedCount
    if itemExtents != nil {
      itemExtents?.insert(contentsOf: repeatElement(itemExtent, count: prependedCount), at: 0)
    }
    scrollState.contentExtent = contentExtent
    let resolved = ScrollAnchor(
      itemIndex: previous.itemIndex + prependedCount,
      offsetFromViewportStart: previous.offsetFromViewportStart
    )
    scrollState.preserveAnchor(oldOrigin: previousOrigin, newOrigin: origin(of: resolved.itemIndex))
    return ConversationPrependAnchor(previous: previous, resolved: resolved)
  }

  /// Appends items and updates the content extent.
  /// - Complexity: O(n + a), where n is the item count and a is the appended count.
  public mutating func append(itemCount appendedCount: Int) {
    precondition(appendedCount >= 0)
    itemCount += appendedCount
    if itemExtents != nil {
      itemExtents?.append(contentsOf: repeatElement(itemExtent, count: appendedCount))
    }
    scrollState.updateContentExtent(contentExtent, anchorToBottom: anchorsNewOutputToBottom)
  }

  /// Scrolls to the maximum content offset.
  /// - Complexity: O(1).
  public mutating func requestScrollToBottom() {
    scrollState = ScrollState(
      viewportExtent: scrollState.viewportExtent,
      contentExtent: scrollState.contentExtent,
      offset: scrollState.maximumOffset
    )
  }

  private var planner: LazyLayoutPlanner {
    LazyLayoutPlanner(itemExtent: itemExtent, spacing: spacing, overscan: overscan)
  }

  private var contentExtent: Double {
    Self.contentExtent(
      itemCount: itemCount,
      itemExtent: itemExtent,
      itemExtents: itemExtents,
      spacing: spacing
    )
  }

  private func origin(of index: Int) -> Double {
    guard let itemExtents else { return planner.origin(of: index) }
    return itemExtents.prefix(index).reduce(0, +) + Double(index) * spacing
  }

  private func itemIndex(at offset: Double) -> Int {
    guard itemCount > 0 else { return 0 }
    guard itemExtents != nil else {
      return min(itemCount - 1, max(0, Int((offset / (itemExtent + spacing)).rounded(.down))))
    }
    var lower = 0
    var upper = itemCount
    while lower < upper {
      let middle = (lower + upper) / 2
      if origin(of: middle) + (itemExtents?[middle] ?? itemExtent) <= offset {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    return min(itemCount - 1, lower)
  }

  private static func contentExtent(
    itemCount: Int,
    itemExtent: Double,
    itemExtents: [Double]?,
    spacing: Double
  ) -> Double {
    guard itemCount > 0 else { return 0 }
    return (itemExtents?.reduce(0, +) ?? Double(itemCount) * itemExtent) + Double(itemCount - 1) * spacing
  }
}
