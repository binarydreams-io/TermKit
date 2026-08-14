/// A point in a cell coordinate space.
public struct CellPoint: Sendable, Hashable {
  /// The horizontal coordinate.
  public var x: Int
  /// The vertical coordinate.
  public var y: Int

  /// Creates a cell point.
  public init(x: Int = 0, y: Int = 0) {
    self.x = x
    self.y = y
  }

  /// The point at the coordinate-space origin.
  public static let zero = CellPoint()

  /// Returns a point offset by the specified distances.
  public func offsetBy(dx: Int = 0, dy: Int = 0) -> CellPoint {
    CellPoint(x: x + dx, y: y + dy)
  }
}

/// A size measured in terminal cells.
public struct CellSize: Sendable, Hashable {
  /// The number of columns.
  public var width: Int
  /// The number of rows.
  public var height: Int

  /// Creates a nonnegative cell size.
  public init(width: Int = 0, height: Int = 0) {
    precondition(width >= 0 && height >= 0, "Cell dimensions must not be negative.")
    self.width = width
    self.height = height
  }

  /// A size with zero width and height.
  public static let zero = CellSize()

  /// A Boolean value that indicates whether either dimension is zero.
  public var isEmpty: Bool {
    width == 0 || height == 0
  }

  /// The number of cells in the size.
  public var cellCount: Int {
    let (count, overflow) = width.multipliedReportingOverflow(by: height)
    precondition(overflow == false, "Cell count exceeds Int.max.")
    return count
  }
}

/// Insets measured from the edges of a cell rectangle.
public struct EdgeInsets: Sendable, Hashable {
  /// The top inset.
  public var top: Int
  /// The leading inset.
  public var leading: Int
  /// The bottom inset.
  public var bottom: Int
  /// The trailing inset.
  public var trailing: Int

  /// Creates edge insets with independent values.
  public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  /// Creates equal insets for all edges.
  public init(all value: Int) {
    self.init(top: value, leading: value, bottom: value, trailing: value)
  }

  /// Creates insets from horizontal and vertical values.
  public init(horizontal: Int = 0, vertical: Int = 0) {
    self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
  }

  /// Insets with zero values for all edges.
  public static let zero = EdgeInsets()

  /// The sum of the leading and trailing insets.
  public var horizontal: Int {
    leading + trailing
  }

  /// The sum of the top and bottom insets.
  public var vertical: Int {
    top + bottom
  }
}

/// A rectangular region in a cell coordinate space.
public struct CellRect: Sendable, Hashable {
  /// The rectangle's origin.
  public var origin: CellPoint
  /// The rectangle's size.
  public var size: CellSize

  /// Creates a rectangle from an origin and size.
  public init(origin: CellPoint = .zero, size: CellSize = .zero) {
    self.origin = origin
    self.size = size
  }

  /// Creates a rectangle from coordinates and dimensions.
  public init(x: Int, y: Int, width: Int, height: Int) {
    self.init(origin: CellPoint(x: x, y: y), size: CellSize(width: width, height: height))
  }

  /// A rectangle with a zero origin and size.
  public static let zero = CellRect()

  /// The minimum horizontal coordinate.
  public var minX: Int {
    origin.x
  }

  /// The minimum vertical coordinate.
  public var minY: Int {
    origin.y
  }

  /// The exclusive maximum horizontal coordinate.
  public var maxX: Int {
    origin.x + size.width
  }

  /// The exclusive maximum vertical coordinate.
  public var maxY: Int {
    origin.y + size.height
  }

  /// The rectangle's width.
  public var width: Int {
    size.width
  }

  /// The rectangle's height.
  public var height: Int {
    size.height
  }

  /// A Boolean value that indicates whether the rectangle is empty.
  public var isEmpty: Bool {
    size.isEmpty
  }

  /// The number of cells in the rectangle.
  public var cellCount: Int {
    size.cellCount
  }

  /// Returns whether the rectangle contains a point.
  public func contains(_ point: CellPoint) -> Bool {
    point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
  }

  /// Returns whether the rectangle contains another rectangle.
  public func contains(_ rect: CellRect) -> Bool {
    rect.isEmpty || (rect.minX >= minX && rect.maxX <= maxX && rect.minY >= minY && rect.maxY <= maxY)
  }

  /// Returns whether this rectangle intersects another rectangle.
  public func intersects(_ other: CellRect) -> Bool {
    isEmpty == false && other.isEmpty == false
      && minX < other.maxX && other.minX < maxX
      && minY < other.maxY && other.minY < maxY
  }

  /// Returns the overlapping region of two rectangles, if one exists.
  public func intersection(_ other: CellRect) -> CellRect? {
    let x0 = Swift.max(minX, other.minX)
    let y0 = Swift.max(minY, other.minY)
    let x1 = Swift.min(maxX, other.maxX)
    let y1 = Swift.min(maxY, other.maxY)
    guard x0 < x1, y0 < y1 else { return nil }
    return CellRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  /// Returns the smallest rectangle that contains both rectangles.
  public func union(_ other: CellRect) -> CellRect {
    if isEmpty {
      return other
    }
    if other.isEmpty {
      return self
    }
    let x0 = Swift.min(minX, other.minX)
    let y0 = Swift.min(minY, other.minY)
    let x1 = Swift.max(maxX, other.maxX)
    let y1 = Swift.max(maxY, other.maxY)
    return CellRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  /// Returns a rectangle adjusted by the specified edge insets.
  public func inset(by insets: EdgeInsets) -> CellRect {
    CellRect(
      x: minX + insets.leading,
      y: minY + insets.top,
      width: Swift.max(0, width - insets.horizontal),
      height: Swift.max(0, height - insets.vertical)
    )
  }

  /// Returns a rectangle with an offset origin.
  public func offsetBy(dx: Int = 0, dy: Int = 0) -> CellRect {
    CellRect(origin: origin.offsetBy(dx: dx, dy: dy), size: size)
  }
}
