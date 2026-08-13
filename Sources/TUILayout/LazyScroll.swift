public struct LazyLayoutPlan: Sendable, Hashable {
    public var visibleRange: Range<Int>
    public var contentExtent: Double

    public init(visibleRange: Range<Int>, contentExtent: Double) {
        self.visibleRange = visibleRange
        self.contentExtent = contentExtent
    }
}

public struct LazyLayoutPlanner: Sendable, Hashable {
    public var itemExtent: Double
    public var spacing: Double
    public var overscan: Int

    public init(itemExtent: Double, spacing: Double = 0, overscan: Int = 1) {
        precondition(itemExtent > 0 && itemExtent.isFinite)
        precondition(spacing >= 0 && spacing.isFinite)
        precondition(overscan >= 0)
        self.itemExtent = itemExtent
        self.spacing = spacing
        self.overscan = overscan
    }

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

    public func origin(of index: Int) -> Double {
        precondition(index >= 0)
        return Double(index) * (itemExtent + spacing)
    }
}

public struct ScrollAnchor: Sendable, Hashable {
    public var itemIndex: Int
    public var offsetFromViewportStart: Double

    public init(itemIndex: Int, offsetFromViewportStart: Double) {
        precondition(itemIndex >= 0)
        self.itemIndex = itemIndex
        self.offsetFromViewportStart = offsetFromViewportStart
    }
}

public struct ScrollState: Sendable, Hashable {
    public var offset: Double
    public var viewportExtent: Double
    public var contentExtent: Double

    public init(offset: Double = 0, viewportExtent: Double, contentExtent: Double) {
        precondition(viewportExtent >= 0 && contentExtent >= 0)
        self.offset = min(max(0, offset), max(0, contentExtent - viewportExtent))
        self.viewportExtent = viewportExtent
        self.contentExtent = contentExtent
    }

    public var maximumOffset: Double {
        max(0, contentExtent - viewportExtent)
    }

    public func isPinnedToBottom(tolerance: Double = 0.5) -> Bool {
        maximumOffset - offset <= max(0, tolerance)
    }

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

    public mutating func preserveAnchor(oldOrigin: Double, newOrigin: Double) {
        offset = min(maximumOffset, max(0, offset + newOrigin - oldOrigin))
    }
}
