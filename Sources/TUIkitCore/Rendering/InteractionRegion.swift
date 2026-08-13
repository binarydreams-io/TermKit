//  TUIKit - Terminal UI Kit for Swift
//  InteractionRegion.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A rectangle measured in terminal cells.
///
/// The origin uses zero-based columns and rows. Width and height are always
/// nonnegative. A wide character occupies two columns but does not change the
/// coordinate model.
public struct TerminalCellRect: Sendable, Equatable {
  /// The zero-based column of the rectangle's leading edge.
  public var x: Int

  /// The zero-based row of the rectangle's top edge.
  public var y: Int

  /// The width in terminal cells.
  public var width: Int

  /// The height in terminal rows.
  public var height: Int

  /// Creates a rectangle in terminal-cell coordinates.
  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = max(0, width)
    self.height = max(0, height)
  }

  /// Whether the rectangle contains no terminal cells.
  public var isEmpty: Bool {
    width == 0 || height == 0
  }

  /// The column immediately after the rectangle's trailing edge.
  public var maxX: Int {
    x + width
  }

  /// The row immediately after the rectangle's bottom edge.
  public var maxY: Int {
    y + height
  }

  /// Returns the overlap between this rectangle and another rectangle.
  ///
  /// - Parameter other: The rectangle to intersect with this rectangle.
  /// - Returns: The overlapping rectangle, or `nil` when there is no overlap.
  public func intersection(_ other: Self) -> Self? {
    let intersectionX = max(x, other.x)
    let intersectionY = max(y, other.y)
    let intersectionMaxX = min(maxX, other.maxX)
    let intersectionMaxY = min(maxY, other.maxY)

    guard intersectionX < intersectionMaxX, intersectionY < intersectionMaxY else {
      return nil
    }

    return Self(
      x: intersectionX,
      y: intersectionY,
      width: intersectionMaxX - intersectionX,
      height: intersectionMaxY - intersectionY
    )
  }

  /// Returns a copy translated by the specified terminal-cell offset.
  ///
  /// - Parameters:
  ///   - x: The horizontal offset in terminal cells.
  ///   - y: The vertical offset in terminal rows.
  /// - Returns: The translated rectangle.
  public func translatedBy(x: Int, y: Int) -> Self {
    Self(x: self.x + x, y: self.y + y, width: width, height: height)
  }
}

/// A stable interaction identifier and its terminal-cell bounds.
///
/// An interaction region contains metadata only. Event handlers remain outside
/// the frame buffer and can resolve the stable identifier after a hit test.
public struct InteractionRegion: Sendable, Equatable {
  /// The stable identifier for the interactive target.
  public let id: String

  /// The target bounds in the containing frame buffer's coordinates.
  public let rect: TerminalCellRect

  /// Creates an interaction region.
  ///
  /// - Parameters:
  ///   - id: The stable identifier for the interactive target.
  ///   - rect: The target bounds in terminal cells.
  public init(id: String, rect: TerminalCellRect) {
    self.id = id
    self.rect = rect
  }
}
