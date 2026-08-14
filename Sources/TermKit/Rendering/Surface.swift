/// An error that occurs while reading or modifying a surface.
public enum SurfaceError: Error, Sendable, Equatable {
  /// A cell point is outside the surface bounds.
  case outOfBounds(CellPoint)
  /// A display width is not one or two cells.
  case invalidDisplayWidth(UInt8)
  /// A clip excludes part of a two-cell grapheme.
  case clippedWideGrapheme(CellPoint)
  /// A two-cell grapheme has an invalid leader or continuation cell.
  case invalidWideCell(CellPoint)
  /// A grapheme remap does not contain an identifier used by the surface.
  case missingGraphemeRemap(GraphemeID)
  /// A style remap does not contain an identifier used by the surface.
  case missingStyleRemap(StyleID)
}

/// A rectangular grid of packed terminal cells.
public struct Surface: Sendable, Equatable {
  /// The surface origin in its cell coordinate space.
  public let origin: CellPoint
  /// The surface dimensions.
  public let size: CellSize
  /// The packed cells in row-major order.
  public private(set) var cells: [PackedCell]

  /// Creates a zero-origin surface filled with a single-width cell.
  public init(size: CellSize, fill: PackedCell = .makeBlank()) {
    self.init(bounds: CellRect(origin: .zero, size: size), fill: fill)
  }

  /// Creates a surface for bounds and fills it with a single-width cell.
  public init(bounds: CellRect, fill: PackedCell = .makeBlank()) {
    precondition(fill.displayWidth == 1 && fill.isContinuation == false, "A surface fill must occupy one cell.")
    self.origin = bounds.origin
    self.size = bounds.size
    self.cells = Array(repeating: fill, count: bounds.size.cellCount)
  }

  /// The surface bounds.
  public var bounds: CellRect {
    CellRect(origin: origin, size: size)
  }

  /// Returns the cell at a point inside the surface bounds.
  public subscript(_ point: CellPoint) -> PackedCell {
    cell(at: point)
  }

  /// Returns the cell at a point inside the surface bounds.
  public func cell(at point: CellPoint) -> PackedCell {
    precondition(bounds.contains(point), "Cell point is outside the surface.")
    return cells[index(of: point)]
  }

  /// Writes a one-cell or two-cell grapheme and returns whether the clip accepted it.
  @discardableResult
  public mutating func write(
    graphemeID: GraphemeID,
    at point: CellPoint,
    styleID: StyleID = .default,
    displayWidth: UInt8 = 1,
    flags: CellFlags = [],
    clip: CellRect? = nil
  ) throws -> Bool {
    guard displayWidth == 1 || displayWidth == 2 else {
      throw SurfaceError.invalidDisplayWidth(displayWidth)
    }
    guard bounds.contains(point) else { throw SurfaceError.outOfBounds(point) }
    let effectiveClip: CellRect
    if let clip {
      guard let intersection = bounds.intersection(clip) else {
        if displayWidth == 2 {
          throw SurfaceError.clippedWideGrapheme(point)
        }
        return false
      }
      effectiveClip = intersection
    } else {
      effectiveClip = bounds
    }
    let atom = CellRect(x: point.x, y: point.y, width: Int(displayWidth), height: 1)
    guard effectiveClip.contains(atom), bounds.contains(atom) else {
      if displayWidth == 2 {
        throw SurfaceError.clippedWideGrapheme(point)
      }
      return false
    }

    clearAtom(at: point, replacingWith: .makeBlank())
    if displayWidth == 2 {
      clearAtom(at: point.offsetBy(dx: 1), replacingWith: .makeBlank())
    }

    let cleanFlags = flags.subtracting(.continuation)
    cells[index(of: point)] = PackedCell(
      graphemeID: graphemeID,
      styleID: styleID,
      displayWidth: displayWidth,
      flags: cleanFlags
    )
    if displayWidth == 2 {
      cells[index(of: point.offsetBy(dx: 1))] = .makeContinuation(graphemeID: graphemeID, styleID: styleID)
    }
    return true
  }

  /// Clears a clipped region with a single-width replacement cell.
  public mutating func clear(_ rect: CellRect? = nil, with replacement: PackedCell = .makeBlank()) {
    precondition(replacement.displayWidth == 1 && replacement.isContinuation == false, "A clear cell must occupy one cell.")
    guard let clipped = bounds.intersection(rect ?? bounds) else { return }
    for y in clipped.minY ..< clipped.maxY {
      for x in clipped.minX ..< clipped.maxX {
        clearAtom(at: CellPoint(x: x, y: y), replacingWith: replacement)
      }
    }
  }

  /// Copies nontransparent cells from a source surface.
  public mutating func compose(
    _ source: Surface,
    at origin: CellPoint = .zero,
    clip: CellRect? = nil
  ) throws {
    try source.validateWideCells()
    guard let destinationClip = bounds.intersection(clip ?? bounds) else { return }
    for sourceY in source.bounds.minY ..< source.bounds.maxY {
      var sourceX = source.bounds.minX
      while sourceX < source.bounds.maxX {
        let sourcePoint = CellPoint(x: sourceX, y: sourceY)
        let cell = source.cell(at: sourcePoint)
        if cell.isContinuation {
          sourceX += 1
          continue
        }
        let width = Int(cell.displayWidth)
        guard width == 1 || width == 2 else {
          sourceX += 1
          continue
        }
        let destination = sourcePoint.offsetBy(dx: origin.x, dy: origin.y)
        let atom = CellRect(x: destination.x, y: destination.y, width: width, height: 1)
        if cell.isTransparent == false, destinationClip.contains(atom), bounds.contains(atom) {
          _ = try write(
            graphemeID: cell.graphemeID,
            at: destination,
            styleID: cell.styleID,
            displayWidth: cell.displayWidth,
            flags: cell.flags,
            clip: destinationClip
          )
        }
        sourceX += width
      }
    }
  }

  /// Validates all wide-grapheme leader and continuation cells.
  public func validateWideCells() throws {
    for y in bounds.minY ..< bounds.maxY {
      for x in bounds.minX ..< bounds.maxX {
        let point = CellPoint(x: x, y: y)
        let cell = cell(at: point)
        if cell.displayWidth == 2 {
          guard x + 1 < bounds.maxX else { throw SurfaceError.invalidWideCell(point) }
          let continuation = self[point.offsetBy(dx: 1)]
          guard continuation.isContinuation,
                continuation.graphemeID == cell.graphemeID,
                continuation.styleID == cell.styleID
          else {
            throw SurfaceError.invalidWideCell(point)
          }
        } else if cell.isContinuation {
          guard x > bounds.minX else { throw SurfaceError.invalidWideCell(point) }
          let leader = self[point.offsetBy(dx: -1)]
          guard leader.displayWidth == 2,
                leader.graphemeID == cell.graphemeID,
                leader.styleID == cell.styleID
          else {
            throw SurfaceError.invalidWideCell(point)
          }
        } else if cell.displayWidth != 1 {
          throw SurfaceError.invalidWideCell(point)
        }
      }
    }
  }

  /// Replaces every grapheme identifier with its rebuilt identifier.
  public mutating func remapGraphemes(using remap: GraphemeRemap) throws {
    for index in cells.indices {
      let cell = cells[index]
      guard let identifier = remap.map(cell.graphemeID) else {
        throw SurfaceError.missingGraphemeRemap(cell.graphemeID)
      }
      cells[index] = PackedCell(
        graphemeID: identifier,
        styleID: cell.styleID,
        displayWidth: cell.displayWidth,
        flags: cell.flags
      )
    }
  }

  /// Replaces every style identifier with its rebuilt identifier.
  public mutating func remapStyles(using remap: StyleRemap) throws {
    for index in cells.indices {
      let cell = cells[index]
      guard let identifier = remap.map(cell.styleID) else {
        throw SurfaceError.missingStyleRemap(cell.styleID)
      }
      cells[index] = PackedCell(
        graphemeID: cell.graphemeID,
        styleID: identifier,
        displayWidth: cell.displayWidth,
        flags: cell.flags
      )
    }
  }

  private func index(of point: CellPoint) -> Int {
    (point.y - origin.y) * size.width + point.x - origin.x
  }

  private mutating func clearAtom(at point: CellPoint, replacingWith replacement: PackedCell) {
    guard bounds.contains(point) else { return }
    let cell = cells[index(of: point)]
    if cell.isContinuation, point.x > 0 {
      let leader = point.offsetBy(dx: -1)
      cells[index(of: leader)] = replacement
      cells[index(of: point)] = replacement
    } else if cell.displayWidth == 2, point.x + 1 < bounds.maxX {
      cells[index(of: point)] = replacement
      cells[index(of: point.offsetBy(dx: 1))] = replacement
    } else {
      cells[index(of: point)] = replacement
    }
  }

  /// Expands a rectangle to include complete two-cell graphemes.
  public func atomExpanded(_ rect: CellRect) -> CellRect {
    guard var expanded = bounds.intersection(rect) else { return .zero }
    for y in expanded.minY ..< expanded.maxY {
      if expanded.minX > bounds.minX, self[CellPoint(x: expanded.minX, y: y)].isContinuation {
        expanded = expanded.union(CellRect(x: expanded.minX - 1, y: y, width: 1, height: 1))
      }
      if expanded.maxX < bounds.maxX {
        let edge = self[CellPoint(x: expanded.maxX - 1, y: y)]
        if edge.displayWidth == 2 {
          expanded = expanded.union(CellRect(x: expanded.maxX, y: y, width: 1, height: 1))
        }
      }
    }
    return expanded
  }
}
