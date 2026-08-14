/// The axes along which a scroll view can move.
public enum ScrollAxis: Sendable, Hashable {
    /// Horizontal scrolling only.
    case horizontal
    /// Vertical scrolling only.
    case vertical
    /// Horizontal and vertical scrolling.
    case both
}

/// Horizontal and vertical scroll state for a viewport.
public struct ScrollViewState: Sendable, Hashable {
    /// The horizontal scroll state.
    public var horizontal: ScrollState
    /// The vertical scroll state.
    public var vertical: ScrollState

    /// Creates scroll state from viewport and content dimensions.
    public init(
        viewport: CellSize,
        content: CellSize,
        offset: CellPoint = .zero
    ) {
        horizontal = ScrollState(
            viewportExtent: Double(viewport.width),
            contentExtent: Double(content.width),
            offset: Double(offset.x)
        )
        vertical = ScrollState(
            viewportExtent: Double(viewport.height),
            contentExtent: Double(content.height),
            offset: Double(offset.y)
        )
    }

    /// The integral cell offset of the viewport.
    public var offset: CellPoint {
        CellPoint(x: Int(horizontal.offset.rounded(.down)), y: Int(vertical.offset.rounded(.down)))
    }

    /// Moves the viewport by floating-point deltas.
    /// - Complexity: O(1).
    public mutating func scroll(dx: Double = 0, dy: Double = 0) {
        horizontal.offset = min(horizontal.maximumOffset, max(0, horizontal.offset + dx))
        vertical.offset = min(vertical.maximumOffset, max(0, vertical.offset + dy))
    }

    /// Moves the viewport to its top edge.
    /// - Complexity: O(1).
    public mutating func scrollToTop() {
        vertical.offset = 0
    }

    /// Moves the viewport to its bottom edge.
    /// - Complexity: O(1).
    public mutating func scrollToBottom() {
        vertical.offset = vertical.maximumOffset
    }

    /// Adjusts both axes to make a rectangle visible.
    /// - Complexity: O(1).
    public mutating func ensureVisible(_ rect: CellRect) {
        horizontal.offset = Self.offsetEnsuringVisible(
            lower: Double(rect.minX),
            upper: Double(rect.maxX),
            state: horizontal
        )
        vertical.offset = Self.offsetEnsuringVisible(
            lower: Double(rect.minY),
            upper: Double(rect.maxY),
            state: vertical
        )
    }

    private static func offsetEnsuringVisible(lower: Double, upper: Double, state: ScrollState) -> Double {
        if lower < state.offset { return max(0, lower) }
        if upper > state.offset + state.viewportExtent {
            return min(state.maximumOffset, max(0, upper - state.viewportExtent))
        }
        return state.offset
    }
}

/// Scrollable content and its semantic state.
public struct ScrollView<Content: Sendable>: Sendable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The enabled scroll axes.
    public var axis: ScrollAxis
    /// The current scroll state.
    public var state: ScrollViewState
    /// The scrollable content.
    public var content: Content

    /// Creates a scroll view.
    public init(
        state: ScrollViewState,
        content: Content,
        id: SemanticID = "scroll-view",
        axis: ScrollAxis = .vertical
    ) {
        self.id = id
        self.axis = axis
        self.state = state
        self.content = content
    }

    /// Creates the scroll view's semantic node.
    /// - Complexity: O(1).
    public func semanticNode(frame: CellRect? = nil, children: [SemanticNode] = []) -> SemanticNode {
        SemanticNode(
            id: id,
            role: .scrollView,
            label: "Scroll view",
            value: "\(state.offset.x),\(state.offset.y)",
            actions: [.scrollForward, .scrollBackward],
            frame: frame,
            children: children
        )
    }
}
