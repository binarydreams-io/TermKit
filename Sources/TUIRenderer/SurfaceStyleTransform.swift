import TUIFoundation

extension Surface {
    public mutating func transformStyles(
        in rect: CellRect,
        styles: inout StyleInterner,
        _ transform: (CellStyle) throws -> CellStyle
    ) throws {
        guard let clipped = bounds.intersection(rect) else { return }
        var transformed: [StyleID: StyleID] = [:]
        for y in clipped.minY..<clipped.maxY {
            for x in clipped.minX..<clipped.maxX {
                let point = CellPoint(x: x, y: y)
                let cell = self[point]
                guard cell.isTransparent == false else { continue }
                let styleID: StyleID
                if let cached = transformed[cell.styleID] {
                    styleID = cached
                } else {
                    guard let style = styles.value(for: cell.styleID) else {
                        throw SurfaceCompositingError.unknownStyle(cell.styleID)
                    }
                    styleID = try styles.intern(transform(style))
                    transformed[cell.styleID] = styleID
                }
                guard cell.isContinuation == false else { continue }
                let atom = CellRect(x: point.x, y: point.y, width: Int(cell.displayWidth), height: 1)
                guard clipped.contains(atom) else { continue }
                _ = try write(
                    graphemeID: cell.graphemeID,
                    styleID: styleID,
                    displayWidth: cell.displayWidth,
                    flags: cell.flags,
                    at: point,
                    clip: clipped
                )
            }
        }
    }
}
