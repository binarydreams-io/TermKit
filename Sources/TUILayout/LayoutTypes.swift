import TUIFoundation
import TUIViewGraph

public struct ProposedCellSize: Sendable, Hashable {
    public var width: Int?
    public var height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        precondition(width.map { $0 >= 0 } ?? true)
        precondition(height.map { $0 >= 0 } ?? true)
        self.width = width
        self.height = height
    }

    public static let unspecified = ProposedCellSize()
    public static let zero = ProposedCellSize(width: 0, height: 0)

    public func replacingUnspecifiedDimensions(by size: CellSize) -> CellSize {
        CellSize(width: width ?? size.width, height: height ?? size.height)
    }
}

public enum HorizontalCellAlignment: Sendable, Hashable {
    case leading
    case center
    case trailing
}

public enum VerticalCellAlignment: Sendable, Hashable {
    case top
    case center
    case bottom
}

public struct CellAlignment: Sendable, Hashable {
    public var horizontal: HorizontalCellAlignment
    public var vertical: VerticalCellAlignment

    public init(
        horizontal: HorizontalCellAlignment = .center,
        vertical: VerticalCellAlignment = .center
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = CellAlignment()
    public static let topLeading = CellAlignment(horizontal: .leading, vertical: .top)
    public static let bottomTrailing = CellAlignment(horizontal: .trailing, vertical: .bottom)
}

public struct LayoutItem: Sendable {
    public let nodeID: NodeID
    private let generationBody: @MainActor @Sendable () -> UInt64
    private let measureBody: @MainActor @Sendable (ProposedCellSize) -> CellSize

    public init(nodeID: NodeID, measure: @escaping @MainActor @Sendable (ProposedCellSize) -> CellSize) {
        self.nodeID = nodeID
        generationBody = { 0 }
        measureBody = measure
    }

    @MainActor
    public init(node: MountedNode, measure: @escaping @MainActor @Sendable (ProposedCellSize) -> CellSize) {
        nodeID = node.id
        generationBody = { node.layoutGeneration }
        measureBody = measure
    }

    public init(nodeID: NodeID, size: CellSize) {
        self.init(nodeID: nodeID) { proposal in
            CellSize(
                width: min(size.width, proposal.width ?? size.width),
                height: min(size.height, proposal.height ?? size.height)
            )
        }
    }

    @MainActor
    public init(node: MountedNode, size: CellSize) {
        self.init(node: node) { proposal in
            CellSize(
                width: min(size.width, proposal.width ?? size.width),
                height: min(size.height, proposal.height ?? size.height)
            )
        }
    }

    @MainActor
    public func measure(in proposal: ProposedCellSize) -> CellSize {
        measureBody(proposal)
    }

    @MainActor
    var layoutGeneration: UInt64 {
        generationBody()
    }
}

public struct LayoutPlacement: Sendable, Hashable {
    public var nodeID: NodeID
    public var frame: CellRect
    public var clip: CellRect?

    public init(nodeID: NodeID, frame: CellRect, clip: CellRect? = nil) {
        debugValidateLayoutRect(frame)
        if let clip { debugValidateLayoutRect(clip) }
        self.nodeID = nodeID
        self.frame = frame
        self.clip = clip
    }
}

public struct LayoutResult: Sendable, Hashable {
    public var size: CellSize
    public var placements: [LayoutPlacement]

    public init(size: CellSize, placements: [LayoutPlacement]) {
        #if DEBUG
        for placement in placements {
            debugValidateLayoutRect(placement.frame)
            if let clip = placement.clip { debugValidateLayoutRect(clip) }
        }
        #endif
        self.size = size
        self.placements = placements
    }
}

@inline(__always)
func layoutAdding(_ lhs: Int, _ rhs: Int) -> Int {
    #if DEBUG
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    precondition(overflow == false, "Layout geometry exceeds the Int cell range.")
    return result
    #else
    lhs + rhs
    #endif
}

@inline(__always)
func layoutSubtracting(_ lhs: Int, _ rhs: Int) -> Int {
    #if DEBUG
    let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
    precondition(overflow == false, "Layout geometry exceeds the Int cell range.")
    return result
    #else
    lhs - rhs
    #endif
}

@inline(__always)
func layoutMultiplying(_ lhs: Int, _ rhs: Int) -> Int {
    #if DEBUG
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    precondition(overflow == false, "Layout geometry exceeds the Int cell range.")
    return result
    #else
    lhs * rhs
    #endif
}

@inline(__always)
func debugValidateLayoutRect(_ rect: CellRect) {
    #if DEBUG
    let (_, xOverflow) = rect.origin.x.addingReportingOverflow(rect.size.width)
    let (_, yOverflow) = rect.origin.y.addingReportingOverflow(rect.size.height)
    precondition(xOverflow == false && yOverflow == false, "Layout rectangle exceeds the Int cell range.")
    #endif
}

public enum StackAxis: Sendable, Hashable {
    case horizontal
    case vertical
}

func alignedOffset(available: Int, occupied: Int, alignment: HorizontalCellAlignment) -> Int {
    switch alignment {
    case .leading: 0
    case .center: max(0, (available - occupied) / 2)
    case .trailing: max(0, available - occupied)
    }
}

func alignedOffset(available: Int, occupied: Int, alignment: VerticalCellAlignment) -> Int {
    switch alignment {
    case .top: 0
    case .center: max(0, (available - occupied) / 2)
    case .bottom: max(0, available - occupied)
    }
}
