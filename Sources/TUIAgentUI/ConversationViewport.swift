import TUILayout
import TUIDesign
import TUIViewGraph

public struct ConversationViewportActions: Sendable {
    public var scrollForward: @MainActor @Sendable () -> Void
    public var scrollBackward: @MainActor @Sendable () -> Void

    public init(
        scrollForward: @escaping @MainActor @Sendable () -> Void = {},
        scrollBackward: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.scrollForward = scrollForward
        self.scrollBackward = scrollBackward
    }
}

public struct ConversationViewportView<Item: AgentContentPresentable>: TUIViewGraph.View {
    public var items: [Item]
    public var state: Binding<ConversationViewportState>
    public var actions: ConversationViewportActions
    public var theme: ResolvedSemanticTheme

    public init(
        items: [Item],
        state: Binding<ConversationViewportState>,
        actions: ConversationViewportActions = ConversationViewportActions(),
        theme: ResolvedSemanticTheme
    ) {
        self.items = items
        self.state = state
        self.actions = actions
        self.theme = theme
    }

    public var graphBody: [NodeDescriptor] {
        AgentComponentView(items: items, state: state, actions: actions, theme: theme).graphBody
    }
}

/// The lazy plan for a transcript. It contains indexes, not transcript items.
public struct ConversationVisiblePlan: Sendable, Hashable {
    public var visibleRange: Range<Int>
    public var contentExtent: Double

    public init(visibleRange: Range<Int>, contentExtent: Double) {
        self.visibleRange = visibleRange
        self.contentExtent = contentExtent
    }
}

/// A transcript anchor before and after older items are prepended.
public struct ConversationPrependAnchor: Sendable, Hashable {
    public var previous: ScrollAnchor
    public var resolved: ScrollAnchor

    public init(previous: ScrollAnchor, resolved: ScrollAnchor) {
        self.previous = previous
        self.resolved = resolved
    }
}

/// A lazy transcript viewport with measured or estimated item extents.
public struct ConversationViewportState: Sendable, Hashable {
    public private(set) var itemCount: Int
    public private(set) var scrollState: ScrollState
    public private(set) var itemExtent: Double
    public private(set) var spacing: Double
    public private(set) var overscan: Int
    public private(set) var itemExtents: [Double]?
    public var anchorsNewOutputToBottom: Bool

    public init(
        itemCount: Int = 0,
        viewportExtent: Double,
        itemExtent: Double,
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
        scrollState = ScrollState(offset: offset, viewportExtent: viewportExtent, contentExtent: extent)
        self.itemExtent = itemExtent
        self.spacing = spacing
        self.overscan = overscan
        anchorsNewOutputToBottom = true
    }

    public var isPinnedToBottom: Bool { scrollState.isPinnedToBottom() }

    public func visiblePlan() -> ConversationVisiblePlan {
        if itemExtents != nil {
            let firstVisible = itemIndex(at: scrollState.offset)
            let lastVisible = itemIndex(at: max(scrollState.offset, scrollState.offset + scrollState.viewportExtent.nextDown))
            let lower = max(0, firstVisible - overscan)
            let upper = min(itemCount, max(lower, lastVisible + 1 + overscan))
            return ConversationVisiblePlan(visibleRange: lower..<upper, contentExtent: contentExtent)
        }
        let plan = planner.plan(
            itemCount: itemCount,
            viewport: scrollState.offset..<(scrollState.offset + scrollState.viewportExtent)
        )
        return ConversationVisiblePlan(visibleRange: plan.visibleRange, contentExtent: plan.contentExtent)
    }

    public func visualAnchor() -> ScrollAnchor {
        guard itemCount > 0 else { return ScrollAnchor(itemIndex: 0, offsetFromViewportStart: 0) }
        let itemIndex = itemIndex(at: scrollState.offset)
        return ScrollAnchor(
            itemIndex: itemIndex,
            offsetFromViewportStart: origin(of: itemIndex) - scrollState.offset
        )
    }

    public mutating func scroll(to offset: Double) {
        scrollState = ScrollState(
            offset: offset,
            viewportExtent: scrollState.viewportExtent,
            contentExtent: scrollState.contentExtent
        )
    }

    public mutating func updateViewportExtent(_ viewportExtent: Double) {
        let wasPinned = isPinnedToBottom
        scrollState = ScrollState(
            offset: wasPinned ? max(0, scrollState.contentExtent - viewportExtent) : scrollState.offset,
            viewportExtent: viewportExtent,
            contentExtent: scrollState.contentExtent
        )
    }

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
            offset: wasPinned
                ? max(0, newExtent - scrollState.viewportExtent)
                : origin(of: anchor.itemIndex) - anchor.offsetFromViewportStart,
            viewportExtent: scrollState.viewportExtent,
            contentExtent: newExtent
        )
    }

    public mutating func updateItemExtents(_ extents: [Double]) {
        precondition(extents.count == itemCount)
        precondition(extents.allSatisfy { $0 > 0 && $0.isFinite })
        let wasPinned = isPinnedToBottom
        let anchor = visualAnchor()
        itemExtents = extents
        let newExtent = contentExtent
        scrollState = ScrollState(
            offset: wasPinned
                ? max(0, newExtent - scrollState.viewportExtent)
                : origin(of: anchor.itemIndex) - anchor.offsetFromViewportStart,
            viewportExtent: scrollState.viewportExtent,
            contentExtent: newExtent
        )
    }

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

    public mutating func append(itemCount appendedCount: Int) {
        precondition(appendedCount >= 0)
        itemCount += appendedCount
        if itemExtents != nil {
            itemExtents?.append(contentsOf: repeatElement(itemExtent, count: appendedCount))
        }
        scrollState.updateContentExtent(contentExtent, anchorToBottom: anchorsNewOutputToBottom)
    }

    public mutating func requestScrollToBottom() {
        scrollState = ScrollState(
            offset: scrollState.maximumOffset,
            viewportExtent: scrollState.viewportExtent,
            contentExtent: scrollState.contentExtent
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
