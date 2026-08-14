/// Caches item measurements by node, proposal, and layout generation.
@MainActor
public final class LayoutCache {
    private struct Key: Hashable {
        var nodeID: NodeID
        var proposal: ProposedCellSize
        var generation: UInt64
    }

    private var measurements: [Key: CellSize] = [:]

    /// The number of measurements served from the cache.
    public private(set) var hitCount = 0
    /// The number of measurements calculated and stored.
    public private(set) var missCount = 0

    /// Creates an empty layout cache.
    public init() {}

    /// Returns a cached measurement or measures and stores the item.
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

    /// Removes cached measurements for a node and its ancestors.
    ///
    /// - Complexity: O(*a* x *m*), where *a* is the ancestor count and *m* is the cache size.
    public func invalidate(_ node: MountedNode) {
        var current: MountedNode? = node
        while let target = current {
            measurements = measurements.filter { $0.key.nodeID != target.id }
            current = target.parent
        }
        node.invalidate(.layout)
    }

    /// Removes all cached measurements.
    public func removeAll() {
        measurements.removeAll(keepingCapacity: true)
    }
}
