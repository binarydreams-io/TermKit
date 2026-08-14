/// Describes the visible items and total extent of a lazy layout.
public struct LazyLayoutPlan: Sendable, Hashable {
    /// The indexes that the layout must realize.
    public var visibleRange: Range<Int>
    /// The total extent of the layout content.
    public var contentExtent: Double

    /// Creates a lazy layout plan.
    public init(visibleRange: Range<Int>, contentExtent: Double) {
        self.visibleRange = visibleRange
        self.contentExtent = contentExtent
    }
}

/// Calculates visible ranges for uniformly sized items.
public struct LazyLayoutPlanner: Sendable, Hashable {
    /// The extent of each item along the scroll axis.
    public var itemExtent: Double
    /// The distance between adjacent items.
    public var spacing: Double
    /// The number of extra items to include on each visible edge.
    public var overscan: Int

    /// Creates a planner for uniformly sized items.
    public init(itemExtent: Double, spacing: Double = 0, overscan: Int = 1) {
        precondition(itemExtent > 0 && itemExtent.isFinite)
        precondition(spacing >= 0 && spacing.isFinite)
        precondition(overscan >= 0)
        self.itemExtent = itemExtent
        self.spacing = spacing
        self.overscan = overscan
    }

    /// Returns the items needed for a viewport.
    public func plan(itemCount: Int, viewport: Range<Double>) -> LazyLayoutPlan {
        precondition(itemCount >= 0)
        precondition(viewport.lowerBound >= 0 && viewport.upperBound >= viewport.lowerBound)
        guard itemCount > 0 else { return LazyLayoutPlan(visibleRange: 0..<0, contentExtent: 0) }
        let stride = itemExtent + spacing
        let contentExtent = Double(itemCount) * stride - spacing
        guard viewport.lowerBound < contentExtent else {
            return LazyLayoutPlan(visibleRange: itemCount..<itemCount, contentExtent: contentExtent)
        }
        if viewport.isEmpty {
            let index = Int((viewport.lowerBound / stride).rounded(.down))
            return LazyLayoutPlan(visibleRange: index..<index, contentExtent: contentExtent)
        }
        let first = max(0, Int((viewport.lowerBound / stride).rounded(.down)) - overscan)
        let visibleUpperBound = min(viewport.upperBound, contentExtent)
        let lastVisible = Int((visibleUpperBound.nextDown / stride).rounded(.down))
        let end = min(itemCount, max(first, lastVisible + 1 + overscan))
        return LazyLayoutPlan(visibleRange: first..<end, contentExtent: contentExtent)
    }

    /// Returns the origin of an item along the scroll axis.
    public func origin(of index: Int) -> Double {
        precondition(index >= 0)
        return Double(index) * (itemExtent + spacing)
    }
}

/// Identifies an item and its position relative to a viewport.
public struct ScrollAnchor: Sendable, Hashable {
    /// The index of the anchored item.
    public var itemIndex: Int
    /// The item's offset from the start of the viewport.
    public var offsetFromViewportStart: Double

    /// Creates a scroll anchor.
    public init(itemIndex: Int, offsetFromViewportStart: Double) {
        precondition(itemIndex >= 0)
        self.itemIndex = itemIndex
        self.offsetFromViewportStart = offsetFromViewportStart
    }
}

/// Stores the scroll offset and viewport geometry.
public struct ScrollState: Sendable, Hashable {
    /// The current offset from the start of the content.
    public var offset: Double
    /// The extent of the visible viewport.
    public var viewportExtent: Double
    /// The total extent of the content.
    public var contentExtent: Double

    /// Creates a clamped scroll state.
    public init(viewportExtent: Double, contentExtent: Double, offset: Double = 0) {
        precondition(viewportExtent >= 0 && contentExtent >= 0)
        self.offset = min(max(0, offset), max(0, contentExtent - viewportExtent))
        self.viewportExtent = viewportExtent
        self.contentExtent = contentExtent
    }

    /// The largest valid scroll offset.
    public var maximumOffset: Double {
        max(0, contentExtent - viewportExtent)
    }

    /// Returns whether the offset is within a tolerance of the bottom.
    public func isPinnedToBottom(tolerance: Double = 0.5) -> Bool {
        maximumOffset - offset <= max(0, tolerance)
    }

    /// Updates the content extent and optionally preserves bottom anchoring.
    public mutating func updateContentExtent(_ newExtent: Double, anchorToBottom: Bool) {
        precondition(newExtent >= 0)
        let wasPinned = isPinnedToBottom()
        contentExtent = newExtent
        if anchorToBottom && wasPinned {
            offset = maximumOffset
        } else {
            offset = min(offset, maximumOffset)
        }
    }

    /// Adjusts the offset to preserve an item's viewport position.
    public mutating func preserveAnchor(oldOrigin: Double, newOrigin: Double) {
        offset = min(maximumOffset, max(0, offset + newOrigin - oldOrigin))
    }
}
