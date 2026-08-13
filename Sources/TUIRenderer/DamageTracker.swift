import TUIFoundation

public struct DamageTracker: Sendable, Hashable {
    public let bounds: CellRect
    public private(set) var rectangles: [CellRect]
    public private(set) var isFullDamage: Bool

    public init(bounds: CellRect) {
        self.bounds = bounds
        rectangles = []
        isFullDamage = false
    }

    public var isEmpty: Bool { rectangles.isEmpty }
    public var damagedCellCount: Int { rectangles.reduce(0) { $0 + $1.cellCount } }

    public mutating func add(_ rect: CellRect) {
        guard isFullDamage == false, var merged = bounds.intersection(rect) else { return }
        var index = 0
        while index < rectangles.count {
            if rectangles[index].intersects(merged) {
                merged = rectangles.remove(at: index).union(merged)
                index = 0
            } else {
                index += 1
            }
        }
        rectangles.append(merged)
        rectangles.sort {
            ($0.minY, $0.minX, $0.maxY, $0.maxX) < ($1.minY, $1.minX, $1.maxY, $1.maxX)
        }
    }

    public mutating func add<S: Sequence>(contentsOf rects: S) where S.Element == CellRect {
        for rect in rects { add(rect) }
    }

    public mutating func invalidateAll() {
        rectangles = bounds.isEmpty ? [] : [bounds]
        isFullDamage = bounds.isEmpty == false
    }

    public mutating func reset() {
        rectangles.removeAll(keepingCapacity: true)
        isFullDamage = false
    }

    public func ranges(inRow row: Int) -> [Range<Int>] {
        var ranges = rectangles.compactMap { rect -> Range<Int>? in
            guard row >= rect.minY && row < rect.maxY else { return nil }
            return rect.minX..<rect.maxX
        }.sorted { $0.lowerBound < $1.lowerBound }
        guard ranges.count > 1 else { return ranges }

        var merged: [Range<Int>] = [ranges.removeFirst()]
        for range in ranges {
            let last = merged.removeLast()
            if range.lowerBound <= last.upperBound {
                merged.append(last.lowerBound..<Swift.max(last.upperBound, range.upperBound))
            } else {
                merged.append(last)
                merged.append(range)
            }
        }
        return merged
    }
}
