import TUIFoundation
import TUILayout

public enum ScrollAxis: Sendable, Hashable {
    case horizontal
    case vertical
    case both
}

public struct ScrollViewState: Sendable, Hashable {
    public var horizontal: ScrollState
    public var vertical: ScrollState

    public init(
        viewport: CellSize,
        content: CellSize,
        offset: CellPoint = .zero
    ) {
        horizontal = ScrollState(
            offset: Double(offset.x),
            viewportExtent: Double(viewport.width),
            contentExtent: Double(content.width)
        )
        vertical = ScrollState(
            offset: Double(offset.y),
            viewportExtent: Double(viewport.height),
            contentExtent: Double(content.height)
        )
    }

    public var offset: CellPoint {
        CellPoint(x: Int(horizontal.offset.rounded(.down)), y: Int(vertical.offset.rounded(.down)))
    }

    public mutating func scroll(dx: Double = 0, dy: Double = 0) {
        horizontal.offset = min(horizontal.maximumOffset, max(0, horizontal.offset + dx))
        vertical.offset = min(vertical.maximumOffset, max(0, vertical.offset + dy))
    }

    public mutating func scrollToTop() {
        vertical.offset = 0
    }

    public mutating func scrollToBottom() {
        vertical.offset = vertical.maximumOffset
    }

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

public struct ScrollView<Content: Sendable>: Sendable {
    public var id: SemanticID
    public var axis: ScrollAxis
    public var state: ScrollViewState
    public var content: Content

    public init(
        id: SemanticID = "scroll-view",
        axis: ScrollAxis = .vertical,
        state: ScrollViewState,
        content: Content
    ) {
        self.id = id
        self.axis = axis
        self.state = state
        self.content = content
    }

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
