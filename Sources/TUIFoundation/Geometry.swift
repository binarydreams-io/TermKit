public struct CellPoint: Sendable, Hashable {
    public var x: Int
    public var y: Int

    public init(x: Int = 0, y: Int = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = CellPoint()

    public func offsetBy(dx: Int = 0, dy: Int = 0) -> CellPoint {
        CellPoint(x: x + dx, y: y + dy)
    }
}

public struct CellSize: Sendable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int = 0, height: Int = 0) {
        precondition(width >= 0 && height >= 0, "Cell dimensions must not be negative.")
        self.width = width
        self.height = height
    }

    public static let zero = CellSize()

    public var isEmpty: Bool {
        width == 0 || height == 0
    }

    public var cellCount: Int {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        precondition(overflow == false, "Cell count exceeds Int.max.")
        return count
    }
}

public struct EdgeInsets: Sendable, Hashable {
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int

    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(all value: Int) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }

    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    public static let zero = EdgeInsets()

    public var horizontal: Int {
        leading + trailing
    }

    public var vertical: Int {
        top + bottom
    }
}

public struct CellRect: Sendable, Hashable {
    public var origin: CellPoint
    public var size: CellSize

    public init(origin: CellPoint = .zero, size: CellSize = .zero) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: CellPoint(x: x, y: y), size: CellSize(width: width, height: height))
    }

    public static let zero = CellRect()

    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width }
    public var maxY: Int { origin.y + size.height }
    public var width: Int { size.width }
    public var height: Int { size.height }
    public var isEmpty: Bool { size.isEmpty }
    public var cellCount: Int { size.cellCount }

    public func contains(_ point: CellPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func contains(_ rect: CellRect) -> Bool {
        rect.isEmpty || (rect.minX >= minX && rect.maxX <= maxX && rect.minY >= minY && rect.maxY <= maxY)
    }

    public func intersects(_ other: CellRect) -> Bool {
        isEmpty == false && other.isEmpty == false
            && minX < other.maxX && other.minX < maxX
            && minY < other.maxY && other.minY < maxY
    }

    public func intersection(_ other: CellRect) -> CellRect? {
        let x0 = Swift.max(minX, other.minX)
        let y0 = Swift.max(minY, other.minY)
        let x1 = Swift.min(maxX, other.maxX)
        let y1 = Swift.min(maxY, other.maxY)
        guard x0 < x1, y0 < y1 else { return nil }
        return CellRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func union(_ other: CellRect) -> CellRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let x0 = Swift.min(minX, other.minX)
        let y0 = Swift.min(minY, other.minY)
        let x1 = Swift.max(maxX, other.maxX)
        let y1 = Swift.max(maxY, other.maxY)
        return CellRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func inset(by insets: EdgeInsets) -> CellRect {
        CellRect(
            x: minX + insets.leading,
            y: minY + insets.top,
            width: Swift.max(0, width - insets.horizontal),
            height: Swift.max(0, height - insets.vertical)
        )
    }

    public func offsetBy(dx: Int = 0, dy: Int = 0) -> CellRect {
        CellRect(origin: origin.offsetBy(dx: dx, dy: dy), size: size)
    }
}
