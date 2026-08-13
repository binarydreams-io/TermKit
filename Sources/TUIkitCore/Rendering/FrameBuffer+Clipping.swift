//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBuffer+Clipping.swift
//
//  Created by LAYERED.work
//  License: MIT

extension FrameBuffer {
  /// Returns the portion of this buffer inside a terminal-cell rectangle.
  ///
  /// The returned buffer uses the clipped rectangle's top-left cell as its
  /// origin. Regions retain their order, and partially visible regions are
  /// reduced to their visible bounds.
  ///
  /// - Parameter rect: The rectangle to retain in this buffer's coordinates.
  /// - Returns: A clipped buffer, or an empty buffer when the bounds do not overlap.
  public func clipped(to rect: TerminalCellRect) -> Self {
    let bufferBounds = TerminalCellRect(x: 0, y: 0, width: width, height: height)
    guard let clippedBounds = bufferBounds.intersection(rect) else {
      return Self()
    }

    let clippedLines = (clippedBounds.y ..< clippedBounds.maxY).map { row in
      Self.clippedLine(
        lines[row],
        fromColumn: clippedBounds.x,
        width: clippedBounds.width
      )
    }
    let clippedRegions = regions.compactMap { region -> InteractionRegion? in
      guard let visibleRect = region.rect.intersection(clippedBounds) else {
        return nil
      }
      return InteractionRegion(
        id: region.id,
        rect: visibleRect.translatedBy(x: -clippedBounds.x, y: -clippedBounds.y)
      )
    }

    return Self(lines: clippedLines, width: clippedBounds.width, regions: clippedRegions)
  }

  /// Returns one line clipped to a terminal-cell range.
  fileprivate static func clippedLine(_ line: String, fromColumn column: Int, width: Int) -> String {
    guard width > 0 else { return "" }

    let leadingBlankCount = cellsInsideCharacter(atColumn: column, in: line)
    let availableWidth = max(0, width - leadingBlankCount)
    let suffix = line.ansiAwareSuffix(droppingVisible: column)
    let content = suffix.ansiAwarePrefix(visibleCount: availableWidth)
    return (String(repeating: " ", count: leadingBlankCount) + content).padToVisibleWidth(width)
  }

  /// Returns the cells after a clip boundary inside a wide character.
  fileprivate static func cellsInsideCharacter(atColumn column: Int, in line: String) -> Int {
    guard column > 0 else { return 0 }

    var consumedCells = 0
    for character in line.stripped {
      let nextBoundary = consumedCells + character.terminalWidth
      if nextBoundary > column {
        return nextBoundary - column
      }
      if nextBoundary == column {
        return 0
      }
      consumedCells = nextBoundary
    }
    return 0
  }
}
