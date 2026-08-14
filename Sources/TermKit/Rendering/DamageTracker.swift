/// Tracks changed regions within fixed cell bounds.
public struct DamageTracker: Sendable, Hashable {
  /// The bounds that constrain tracked damage.
  public let bounds: CellRect
  /// The sorted, nonoverlapping damaged rectangles.
  public private(set) var rectangles: [CellRect]
  /// A Boolean value that indicates whether all nonempty bounds are damaged.
  public private(set) var isFullDamage: Bool

  /// Creates an empty damage tracker for fixed bounds.
  public init(bounds: CellRect) {
    self.bounds = bounds
    self.rectangles = []
    self.isFullDamage = false
  }

  /// A Boolean value that indicates whether the tracker contains no damaged rectangles.
  public var isEmpty: Bool {
    rectangles.isEmpty
  }

  /// The total number of cells in all damaged rectangles.
  ///
  /// - Complexity: O(*n*), where *n* is the number of damaged rectangles.
  public var damagedCellCount: Int {
    rectangles.reduce(0) { $0 + $1.cellCount }
  }

  /// Adds a damaged rectangle after clipping and merging it with existing damage.
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

  /// Adds a sequence of damaged rectangles.
  public mutating func add(contentsOf rects: some Sequence<CellRect>) {
    for rect in rects {
      add(rect)
    }
  }

  /// Marks all nonempty bounds as damaged.
  public mutating func invalidateAll() {
    rectangles = bounds.isEmpty ? [] : [bounds]
    isFullDamage = bounds.isEmpty == false
  }

  /// Removes all tracked damage.
  public mutating func reset() {
    rectangles.removeAll(keepingCapacity: true)
    isFullDamage = false
  }

  /// Returns the merged damaged column ranges in a row.
  public func ranges(inRow row: Int) -> [Range<Int>] {
    var ranges = rectangles.compactMap { rect -> Range<Int>? in
      guard row >= rect.minY, row < rect.maxY else { return nil }
      return rect.minX ..< rect.maxX
    }.sorted { $0.lowerBound < $1.lowerBound }
    guard ranges.count > 1 else { return ranges }

    var merged: [Range<Int>] = [ranges.removeFirst()]
    for range in ranges {
      let last = merged.removeLast()
      if range.lowerBound <= last.upperBound {
        merged.append(last.lowerBound ..< Swift.max(last.upperBound, range.upperBound))
      } else {
        merged.append(last)
        merged.append(range)
      }
    }
    return merged
  }
}
