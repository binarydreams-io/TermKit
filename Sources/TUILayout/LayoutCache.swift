import TUIFoundation
import TUIViewGraph

@MainActor
public final class LayoutCache {
    private struct Key: Hashable {
        var nodeID: NodeID
        var proposal: ProposedCellSize
        var generation: UInt64
    }

    private var measurements: [Key: CellSize] = [:]

    public private(set) var hitCount = 0
    public private(set) var missCount = 0

    public init() {}

    public func measure(_ item: LayoutItem, in proposal: ProposedCellSize) -> CellSize {
        let key = Key(nodeID: item.nodeID, proposal: proposal, generation: item.layoutGeneration)
        if let size = measurements[key] {
            hitCount += 1
            return size
        }
        let size = item.measure(in: proposal)
        measurements[key] = size
        missCount += 1
        return size
    }

    public func invalidate(_ node: MountedNode) {
        var current: MountedNode? = node
        while let target = current {
            measurements = measurements.filter { $0.key.nodeID != target.id }
            current = target.parent
        }
        node.invalidate(.layout)
    }

    public func removeAll() {
        measurements.removeAll(keepingCapacity: true)
    }
}
